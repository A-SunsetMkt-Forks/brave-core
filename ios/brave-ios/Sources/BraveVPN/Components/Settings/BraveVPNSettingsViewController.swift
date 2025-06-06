// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShared
import BraveStore
import BraveUI
import GuardianConnect
import Preferences
import Shared
import Static
import SwiftUI
import UIKit
import os.log

public class BraveVPNSettingsViewController: TableViewController {

  public var openURL: ((URL) -> Void)?
  let iapObserver: BraveVPNInAppPurchaseObserver

  public init(iapObserver: BraveVPNInAppPurchaseObserver) {
    self.iapObserver = iapObserver

    super.init(style: .insetGrouped)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError() }

  private var credentialSummary: SkusCredentialSummary?

  // Cell/section tags so we can update them dynamically.
  private let serverSectionId = "server"
  private let subscriptionStatusSectionId = "subscriptionStatus"
  private let locationCellId = "location"
  private let protocolCellId = "protocol"
  private let resetCellId = "reset"
  private let vpnStatusSectionCellId = "vpnStatus"
  private let vpnStatusProductTypeCellId = "vpnStatusProductType"
  private let vpnStatusExpiryDateCellId = "vpnStatusExpiryDate"
  private let vpnSmartProxySectionCellId = "vpnSmartProxy"
  private let vpnKillSwitchSectionCellId = "vpnKillSwitch"

  private var vpnConnectionStatusSwitch: SwitchAccessoryView?

  private var vpnReconfigurationPending = false {
    didSet {
      DispatchQueue.main.async {
        self.vpnConnectionStatusSwitch?.isEnabled = !self.vpnReconfigurationPending
      }
    }
  }

  /// View to show when the vpn config reset is pending.
  private var overlayView: UIView?

  private var isLoading: Bool = false {
    didSet {
      overlayView?.removeFromSuperview()

      if !isLoading { return }

      let overlay = UIView().then {
        $0.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let activityIndicator = UIActivityIndicatorView().then {
          $0.style = .large
          $0.color = .white
          $0.startAnimating()
          $0.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        $0.addSubview(activityIndicator)
      }

      view.addSubview(overlay)
      overlay.frame = CGRect(size: tableView.contentSize)

      overlayView = overlay
    }
  }

  private var vpnProductStatusInfo: (subscriptionStatus: String, statusDetailColor: UIColor) {
    if Preferences.VPN.vpnReceiptStatus.value
      == BraveVPN.ReceiptResponse.Status.retryPeriod.rawValue
    {
      return (Strings.VPN.vpnActionUpdatePaymentMethodSettingsText, .braveErrorLabel)
    }

    if BraveVPN.vpnState == .expired {
      return (Strings.VPN.subscriptionStatusExpired, .braveErrorLabel)
    } else {
      return (BraveVPN.subscriptionName, .braveLabel)
    }
  }

  @MainActor
  func fetchCredentialSummary() async -> SkusCredentialSummary? {
    self.isLoading = true
    defer { self.isLoading = false }

    if BraveStoreSDK.shared.vpnSubscriptionStatus != nil {
      return nil
    }

    do {
      return try await BraveSkusSDK.shared.credentialsSummary(for: .vpn)
    } catch {
      Logger.module.error("Error Fetching VPN Skus Credential Summary: \(error)")
    }

    return nil
  }

  private var linkReceiptRows: [Row] {
    var rows = [Row]()

    rows.append(
      Row(
        text: Strings.VPN.settingsLinkReceipt,
        selection: { [unowned self] in
          Task {
            try await BraveVPNInAppPurchaseObserver.refreshReceipt()
          }
          openURL?(.brave.braveVPNLinkReceiptProd)
        },
        cellClass: ButtonCell.self
      )
    )

    if BraveVPN.isSandbox {
      rows += [
        Row(
          text: "[Staging] Link Receipt",
          selection: { [unowned self] in
            Task {
              try await BraveVPNInAppPurchaseObserver.refreshReceipt()
            }
            openURL?(.brave.braveVPNLinkReceiptStaging)
          },
          cellClass: ButtonCell.self
        ),
        Row(
          text: "[Dev] Link Receipt",
          selection: { [unowned self] in
            Task {
              try await BraveVPNInAppPurchaseObserver.refreshReceipt()
            }
            openURL?(.brave.braveVPNLinkReceiptDev)
          },
          cellClass: ButtonCell.self
        ),
      ]
    }

    rows.append(
      Row(
        text: Strings.VPN.settingsViewReceipt,
        selection: { [unowned self] in
          let controller = UIHostingController(rootView: StoreKitReceiptSimpleView())
          self.navigationController?.pushViewController(controller, animated: true)
        },
        cellClass: ButtonCell.self
      )
    )

    return rows
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    title = Strings.VPN.vpnName
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(vpnConfigChanged(_:)),
      name: .NEVPNStatusDidChange,
      object: nil
    )

    let vpnEnabledToggleView = SwitchAccessoryView(
      initialValue: BraveVPN.isConnected,
      valueChange: { vpnOn in
        if vpnOn {
          BraveVPN.reconnect()
        } else {
          BraveVPN.disconnect()
        }
      }
    )

    let vpnSmartProxyToggleView = BraveVPNLinkSwitchView(
      isOn: { BraveVPN.isSmartProxyRoutingEnabled },
      valueChange: { isSmartProxyEnabled in
        BraveVPN.isSmartProxyRoutingEnabled = isSmartProxyEnabled
      },
      openURL: openURL
    )

    let vpnKillSwitchToggleView = BraveVPNLinkSwitchView(
      isOn: { BraveVPN.isKillSwitchEnabled },
      valueChange: { isKillSwitchEnabled in
        BraveVPN.isKillSwitchEnabled = isKillSwitchEnabled
      },
      openURL: openURL
    )

    if Preferences.VPN.vpnReceiptStatus.value
      == BraveVPN.ReceiptResponse.Status.retryPeriod.rawValue
    {
      vpnEnabledToggleView.onTintColor = .braveErrorLabel
    }

    self.vpnConnectionStatusSwitch = vpnEnabledToggleView

    let vpnStatusSection = Section(
      rows: [
        Row(
          text: Strings.VPN.settingsVPNEnabled,
          accessory: .view(vpnEnabledToggleView),
          uuid: vpnStatusSectionCellId
        ),
        Row(
          text: Strings.VPN.settingsVPNSmartProxyEnabled,
          detailText: String.localizedStringWithFormat(
            Strings.VPN.settingsVPNSmartProxyDescription,
            URL.brave.braveVPNSmartProxySupport.absoluteString
          ),
          accessory: .view(vpnSmartProxyToggleView),
          cellClass: BraveVPNLinkSwitchCell.self,
          uuid: vpnSmartProxySectionCellId
        ),
        Row(
          text: Strings.VPN.settingsVPNKillSwitchTitle,
          detailText: String.localizedStringWithFormat(
            Strings.VPN.settingsVPNKillSwitchDescription,
            URL.brave.braveVPNKillSwitchSupport.absoluteString
          ),
          accessory: .view(vpnKillSwitchToggleView),
          cellClass: BraveVPNLinkSwitchCell.self,
          uuid: vpnKillSwitchSectionCellId
        ),
      ],
      uuid: vpnStatusSectionCellId
    )

    let (subscriptionStatus, statusDetailColor) = vpnProductStatusInfo
    let expiration = BraveVPN.vpnState == .expired ? "-" : expirationDate

    let subscriptionSection =
      Section(
        header: .title(Strings.VPN.settingsSubscriptionSection),
        rows: [
          Row(
            text: Strings.VPN.settingsSubscriptionStatus,
            detailText: subscriptionStatus,
            cellClass: ColoredDetailCell.self,
            context: [ColoredDetailCell.colorKey: statusDetailColor],
            uuid: vpnStatusProductTypeCellId
          ),
          Row(
            text: Strings.VPN.settingsSubscriptionExpiration,
            detailText: expiration,
            uuid: vpnStatusExpiryDateCellId
          ),
          Row(
            text: Strings.VPN.settingsManageSubscription,
            selection: {
              guard let url = URL.apple.manageSubscriptions else { return }
              if UIApplication.shared.canOpenURL(url) {
                // Opens Apple's 'manage subscription' screen.
                UIApplication.shared.open(url, options: [:])
              }
            },
            cellClass: ButtonCell.self
          ),
          Row(
            text: Strings.VPN.settingsRedeemOfferCode,
            selection: {
              self.isLoading = false
              // Open the redeem code sheet
              SKPaymentQueue.default().presentCodeRedemptionSheet()
            },
            cellClass: ButtonCell.self
          ),
        ] + linkReceiptRows,
        footer: .title(Strings.VPN.settingsLinkReceiptFooter),
        uuid: subscriptionStatusSectionId
      )

    let locationCity = BraveVPN.serverLocationDetailed.city ?? "-"
    let locationCountry = BraveVPN.serverLocationDetailed.country ?? hostname

    let userPreferredTunnelProtocol = GRDTransportProtocol.getUserPreferredTransportProtocol()
    let transportProtocol = GRDTransportProtocol.prettyTransportProtocolString(
      for: userPreferredTunnelProtocol
    )

    let serverSection = Section(
      header: .title(Strings.VPN.settingsServerSection),
      rows: [
        Row(
          text: locationCountry,
          detailText: locationCity,
          selection: { [unowned self] in
            self.selectServerTapped()
          },
          image: BraveVPN.serverLocation.isoCode?.regionFlagImage
            ?? UIImage(braveSystemNamed: "leo.globe"),
          accessory: .disclosureIndicator,
          cellClass: MultilineSubtitleCell.self,
          uuid: locationCellId
        ),
        Row(
          text: Strings.VPN.settingsTransportProtocol,
          detailText: transportProtocol,
          selection: { [unowned self] in
            self.selectProtocolTapped()
          },
          accessory: .disclosureIndicator,
          uuid: protocolCellId
        ),
        Row(
          text: Strings.VPN.settingsResetConfiguration,
          selection: { [unowned self] in
            self.resetConfigurationTapped()
          },
          cellClass: ButtonCell.self,
          uuid: resetCellId
        ),
      ],
      uuid: serverSectionId
    )

    let techSupportSection = Section(
      header: .title(Strings.support.capitalized),
      rows: [
        Row(
          text: Strings.VPN.settingsContactSupport,
          selection: { [unowned self] in
            self.sendContactSupportEmail()
          },
          accessory: .disclosureIndicator
        ),
        Row(
          text: Strings.VPN.settingsFAQ,
          selection: { [unowned self] in
            self.openURL?(.brave.braveVPNFaq)
          },
          cellClass: ButtonCell.self
        ),
      ]
    )

    dataSource.sections = [
      vpnStatusSection,
      subscriptionSection,
      serverSection,
      techSupportSection,
    ]

    Task { @MainActor in
      self.credentialSummary = await fetchCredentialSummary()
      self.updateSubscriptionStatus()
      self.updateSubscriptionExpiryDate()
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private var hostname: String {
    BraveVPN.hostname?.components(separatedBy: ".").first ?? "-"
  }

  private var expirationDate: String {
    let dateFormatter = DateFormatter().then {
      $0.locale = Locale.current
      $0.dateStyle = .short
    }

    if let order = credentialSummary?.order, let expiresAt = order.expiresAt {
      Preferences.VPN.expirationDate.value = expiresAt
      return dateFormatter.string(from: expiresAt)
    }

    guard let expirationDate = Preferences.VPN.expirationDate.value else {
      return ""
    }

    return dateFormatter.string(from: expirationDate)
  }

  private func updateServerInfo() {
    guard
      let locationIndexPath =
        dataSource
        .indexPath(rowUUID: locationCellId, sectionUUID: serverSectionId)
    else { return }

    guard
      let protocolIndexPath =
        dataSource
        .indexPath(rowUUID: protocolCellId, sectionUUID: serverSectionId)
    else { return }

    dataSource.sections[locationIndexPath.section].rows[locationIndexPath.row]
      .text = BraveVPN.serverLocationDetailed.city ?? "-"
    dataSource.sections[locationIndexPath.section].rows[locationIndexPath.row]
      .detailText = BraveVPN.serverLocationDetailed.country ?? hostname
    dataSource.sections[locationIndexPath.section].rows[locationIndexPath.row]
      .image =
      BraveVPN.serverLocation.isoCode?.regionFlagImage ?? UIImage(braveSystemNamed: "leo.globe")

    dataSource.sections[protocolIndexPath.section].rows[protocolIndexPath.row]
      .detailText = GRDTransportProtocol.prettyTransportProtocolString(
        for: GRDTransportProtocol.getUserPreferredTransportProtocol()
      )
  }

  private func updateSubscriptionStatus() {
    if let credentialSummary = credentialSummary {
      Preferences.VPN.subscriptionProductId.value = credentialSummary.order.items.first?.sku

      guard
        let statusIndexPath =
          dataSource
          .indexPath(rowUUID: vpnStatusProductTypeCellId, sectionUUID: subscriptionStatusSectionId)
      else { return }

      let (subscriptionStatus, statusDetailColor) = vpnProductStatusInfo
      dataSource.sections[statusIndexPath.section].rows[statusIndexPath.row]
        .detailText = subscriptionStatus
      dataSource.sections[statusIndexPath.section].rows[statusIndexPath.row]
        .context = [ColoredDetailCell.colorKey: statusDetailColor]
    }
  }

  private func updateSubscriptionExpiryDate() {
    guard
      let expiryDateIndexPath =
        dataSource
        .indexPath(rowUUID: vpnStatusExpiryDateCellId, sectionUUID: subscriptionStatusSectionId)
    else { return }

    let expiration = BraveVPN.vpnState == .expired ? "-" : expirationDate
    dataSource.sections[expiryDateIndexPath.section].rows[expiryDateIndexPath.row]
      .text = Strings.VPN.settingsSubscriptionExpiration
    dataSource.sections[expiryDateIndexPath.section].rows[expiryDateIndexPath.row]
      .detailText = expiration
  }

  private func sendContactSupportEmail() {
    navigationController?.pushViewController(BraveVPNContactFormViewController(), animated: true)
  }

  private func resetConfigurationTapped() {
    let alert = UIAlertController(
      title: Strings.VPN.vpnResetAlertTitle,
      message: Strings.VPN.vpnResetAlertBody,
      preferredStyle: .actionSheet
    )

    let cancel = UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel)
    let reset = UIAlertAction(
      title: Strings.VPN.vpnResetButton,
      style: .destructive,
      handler: { [weak self] _ in
        guard let self = self else { return }
        self.vpnReconfigurationPending = true
        self.isLoading = true
        Logger.module.debug("Reconfiguring the vpn")

        BraveVPN.reconfigureVPN { success in
          Logger.module.debug("Reconfiguration suceedeed: \(success)")
          // Small delay before unlocking UI because enabling vpn
          // takes a moment after we call to connect to the vpn.
          DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isLoading = false
            self.vpnReconfigurationPending = false
            self.updateServerInfo()
            self.showVPNResetAlert(success: success)
          }
        }
      }
    )

    alert.addAction(cancel)
    alert.addAction(reset)

    if UIDevice.current.userInterfaceIdiom == .pad {
      alert.popoverPresentationController?.permittedArrowDirections = [.down, .up]

      if let resetCellIndexPath =
        dataSource
        .indexPath(rowUUID: resetCellId, sectionUUID: serverSectionId)
      {
        let cell = tableView.cellForRow(at: resetCellIndexPath)

        alert.popoverPresentationController?.sourceView = cell
        alert.popoverPresentationController?.sourceRect = cell?.bounds ?? .zero
      } else {
        alert.popoverPresentationController?.sourceView = self.view
        alert.popoverPresentationController?.sourceRect = self.view.bounds
      }
    }

    present(alert, animated: true)
  }

  private func selectServerTapped() {
    if BraveVPN.allRegions.isEmpty {
      let alert = UIAlertController(
        title: Strings.VPN.vpnConfigGenericErrorTitle,
        message: Strings.VPN.settingsFailedToFetchServerList,
        preferredStyle: .alert
      )
      alert.addAction(.init(title: Strings.OKString, style: .default))
      // Failed to fetch regions at app init or first vpn configuration.
      // Let's try again here.
      BraveVPN.populateRegionDataIfNecessary()
      present(alert, animated: true)
      return
    }

    let vpnRegionListView = BraveVPNRegionListView { [weak self] _ in
      self?.updateServerInfo()

      let controller = PopupViewController(
        rootView: BraveVPNRegionConfirmationView(
          country: BraveVPN.serverLocationDetailed.country,
          city: BraveVPN.serverLocationDetailed.city,
          countryISOCode: BraveVPN.serverLocation.isoCode
        ),
        isDismissable: true
      )
      self?.present(controller, animated: true)
      Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak controller] _ in
        controller?.dismiss(animated: true)
      }
    }
    let vc = UIHostingController(rootView: vpnRegionListView)
    vc.title = Strings.VPN.vpnRegionListServerScreenTitle
    navigationController?.pushViewController(vc, animated: true)
  }

  private func selectProtocolTapped() {
    let vc = BraveVPNProtocolPickerViewController()
    navigationController?.pushViewController(vc, animated: true)
  }

  private func showVPNResetAlert(success: Bool) {
    let alert = UIAlertController(
      title: success ? Strings.VPN.resetVPNSuccessTitle : Strings.VPN.resetVPNErrorTitle,
      message: success ? Strings.VPN.resetVPNSuccessBody : Strings.VPN.resetVPNErrorBody,
      preferredStyle: .alert
    )

    if success {
      let okAction = UIAlertAction(title: Strings.OKString, style: .default)
      alert.addAction(okAction)
    } else {
      alert.addAction(UIAlertAction(title: Strings.close, style: .cancel, handler: nil))
      alert.addAction(
        UIAlertAction(
          title: Strings.VPN.resetVPNErrorButtonActionTitle,
          style: .default,
          handler: { [weak self] _ in
            self?.resetConfigurationTapped()
          }
        )
      )
    }

    present(alert, animated: true)
  }

  @objc func vpnConfigChanged(_ notification: NSNotification) {
    guard let vpnConnection = notification.object as? NEVPNConnection else {
      return
    }

    switch vpnConnection.status {
    case .connecting, .disconnecting, .reasserting:
      isLoading = true
    case .invalid:
      vpnConnectionStatusSwitch?.isOn = false
    case .connected, .disconnected:
      vpnConnectionStatusSwitch?.isOn = BraveVPN.isConnected
    @unknown default:
      assertionFailure()
      break
    }

    isLoading = false
  }
}

// MARK: - IAPObserverDelegate

extension BraveVPNSettingsViewController: BraveVPNInAppPurchaseObserverDelegate {
  public func purchasedOrRestoredProduct(validateReceipt: Bool) {
    DispatchQueue.main.async {
      self.isLoading = false
    }

    if validateReceipt {
      Task {
        _ = try await BraveVPN.validateReceiptData()
      }
    }
  }

  public func purchaseFailed(error: BraveVPNInAppPurchaseObserver.PurchaseError) {
    // Handle Offer Code error
    guard isLoading else {
      return
    }

    handleOfferCodeError(error: error)
  }

  public func handlePromotedInAppPurchase() {
    // No-op
  }

  private func handleOfferCodeError(error: BraveVPNInAppPurchaseObserver.PurchaseError) {
    DispatchQueue.main.async {
      self.isLoading = false

      let message = Strings.VPN.vpnErrorOfferCodeFailedBody

      let alert = UIAlertController(
        title: Strings.VPN.vpnErrorPurchaseFailedTitle,
        message: message,
        preferredStyle: .alert
      )
      let ok = UIAlertAction(title: Strings.OKString, style: .default, handler: nil)
      alert.addAction(ok)
      self.present(alert, animated: true)
    }
  }
}
