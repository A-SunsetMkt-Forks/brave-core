// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import BraveUI
import CoreData
import Data
import Preferences
import Shared
import UIKit
import Web
import os.log

protocol SyncStatusDelegate: AnyObject {
  func syncStatusChanged()
}

class SyncSettingsTableViewController: SyncViewController, UITableViewDelegate,
  UITableViewDataSource
{

  private enum Sections: Int, CaseIterable {
    case deviceList, syncTypes, otherActions
  }

  private enum SyncDataTypes: Int, CaseIterable {
    case bookmarks = 0
    case history
    case passwords
    case openTabs

    var title: String {
      switch self {
      case .bookmarks:
        return Strings.bookmarksMenuItem
      case .history:
        return Strings.historyMenuItem
      case .passwords:
        return Strings.passwordsMenuItem
      case .openTabs:
        return Strings.openTabsMenuItem
      }
    }
  }

  private enum AlertActionType {
    case lastDeviceLeft
    case currentDeviceLeft
    case otherDeviceLeft
    case syncChainDeleteConfirmation
    case syncChainDeleteError
  }

  weak var syncStatusDelegate: SyncStatusDelegate?

  // MARK: Private

  private let braveCoreMain: BraveProfileController
  private let syncAPI: BraveSyncAPI
  private let syncProfileService: BraveSyncProfileServiceIOS

  private var syncDeviceObserver: AnyObject?
  private var syncServiceObserver: AnyObject?
  private var devices = [BraveSyncDevice]()

  /// After synchronization is completed, user needs to tap on `Done` to go back.
  /// Standard navigation is disabled then.
  private var isModallyPresented = false

  private var tableView = UITableView(frame: .zero, style: .insetGrouped)
  private let loadingView = UIView().then {
    $0.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
    $0.isHidden = true
  }
  private let loadingSpinner = UIActivityIndicatorView(style: .large).then {
    $0.startAnimating()
  }

  private lazy var emptyStateOverlayView = EmptyStateOverlayView(
    overlayDetails: EmptyOverlayStateDetails(
      title: Strings.OpenTabs.noDevicesSyncChainPlaceholderViewTitle,
      description: Strings.OpenTabs.noDevicesSyncChainPlaceholderViewDescription,
      icon: UIImage(systemName: "exclamationmark.arrow.triangle.2.circlepath")
    )
  )

  // MARK: Lifecycle

  init(
    isModallyPresented: Bool = false,
    braveCoreMain: BraveProfileController,
    windowProtection: WindowProtection?
  ) {
    self.isModallyPresented = isModallyPresented
    self.braveCoreMain = braveCoreMain
    self.syncAPI = braveCoreMain.syncAPI
    self.syncProfileService = braveCoreMain.syncProfileService

    // Local Authentication (Biometric - Pincode) needed only for actions
    // Enabling - disabling password sync and add new device
    super.init(
      windowProtection: windowProtection,
      requiresAuthentication: false,
      isModallyPresented: isModallyPresented,
      dismissPresenter: false
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = Strings.Sync.syncTitle

    tableView.do {
      $0.dataSource = self
      $0.delegate = self
      $0.tableHeaderView = makeInformationHeaderTextView(with: Strings.Sync.settingsHeader)
    }

    doLayout()

    syncServiceObserver = syncAPI.addServiceStateObserver { [weak self] in
      // Observe Sync State in order to determine if the sync chain is deleted
      // from another device - Clean local sync chain
      self?.restartSyncSetupIfNecessary()
    }

    syncDeviceObserver = syncAPI.addDeviceStateObserver { [weak self] in
      self?.updateDeviceList()
    }

    restartSyncSetupIfNecessary()
    updateDeviceList()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    if isModallyPresented {
      navigationController?.interactivePopGestureRecognizer?.isEnabled = false
      navigationItem.setHidesBackButton(true, animated: false)
      navigationItem.leftBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .done,
        target: self,
        action: #selector(doneTapped)
      )
    }
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()

    guard let headerView = tableView.tableHeaderView else { return }

    let newSize = headerView.systemLayoutSizeFitting(
      CGSize(width: self.view.bounds.width, height: 0)
    )
    headerView.frame.size.height = newSize.height
  }

  private func restartSyncSetupIfNecessary() {
    if syncAPI.shouldLeaveSyncGroup {
      syncAPI.leaveSyncGroup()
      navigationController?.popToRootViewController(animated: true)
    }
  }

  private func doLayout() {
    view.addSubview(tableView)
    loadingView.addSubview(loadingSpinner)
    view.addSubview(loadingView)

    tableView.snp.makeConstraints {
      $0.edges.equalTo(view)
    }

    loadingView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }

    loadingSpinner.snp.makeConstraints {
      $0.center.equalTo(loadingView)
    }
  }

  private func presentAlertPopup(for type: AlertActionType, device: BraveSyncDevice? = nil) {
    var title: String?
    var message: String?
    var removeButtonName: String?
    let deviceName = device?.name?.htmlEntityEncodedString ?? Strings.Sync.removeDeviceDefaultName

    switch type {
    case .lastDeviceLeft:
      title = String(format: Strings.Sync.removeLastDeviceTitle, deviceName)
      message = Strings.Sync.removeLastDeviceMessage
      removeButtonName = Strings.Sync.removeLastDeviceRemoveButtonName
    case .currentDeviceLeft:
      title = String(
        format: Strings.Sync.removeCurrentDeviceTitle,
        "\(deviceName) (\(Strings.Sync.thisDevice))"
      )
      message = Strings.Sync.removeCurrentDeviceMessage
      removeButtonName = Strings.Sync.removeDevice
    case .otherDeviceLeft:
      title = String(format: Strings.Sync.removeOtherDeviceTitle, deviceName)
      message = Strings.Sync.removeOtherDeviceMessage
      removeButtonName = Strings.Sync.removeDevice
    case .syncChainDeleteConfirmation:
      title = Strings.Sync.deleteAccountAlertTitle
      message =
        "\(Strings.Sync.deleteAccountAlertDescriptionPart1)\n\n\(Strings.Sync.deleteAccountAlertDescriptionPart2)\n\n\(Strings.Sync.deleteAccountAlertDescriptionPart3)"
      removeButtonName = Strings.delete
    case .syncChainDeleteError:
      title = Strings.Sync.chainAccountDeletionErrorTitle
      message = Strings.Sync.chainAccountDeletionErrorDescription
      removeButtonName = Strings.OKString
    }

    guard let popupTitle = title, let popupMessage = message, let popupButtonName = removeButtonName
    else { fatalError() }

    let popup = AlertPopupView(title: popupTitle, message: popupMessage)

    popup.addButton(title: Strings.cancelButtonTitle) { return .flyDown }
    popup.addButton(title: popupButtonName, type: .destructive) {
      switch type {
      case .lastDeviceLeft, .currentDeviceLeft:
        self.syncAPI.leaveSyncGroup()
        self.navigationController?.popToRootViewController(animated: true)
      case .otherDeviceLeft:
        if let guid = device?.guid {
          self.syncAPI.removeDeviceFromSyncGroup(deviceGuid: guid)
        }
      case .syncChainDeleteConfirmation:
        self.doIfConnected {
          // Observers have to be removed before permanentlyDeleteAccount is called
          // to prevent glitch in settings screen
          self.syncAPI.removeAllObservers()
          // Start  loading and diable navigation while delete action is happening
          self.enableNavigationPrevention()

          // Permanently Delete action is called on brave-core side
          self.syncAPI.permanentlyDeleteAccount { status in

            switch status {
            case .throttled, .partialFailure, .transientError:
              self.presentAlertPopup(for: .syncChainDeleteError)
            default:
              // Clearing local preferences and calling reset chain on brave-core side
              self.syncAPI.leaveSyncGroup(preservingObservers: true)
              self.syncStatusDelegate?.syncStatusChanged()
            }

            self.disableNavigationPrevention()

            if self.isModallyPresented {
              self.navigationController?.dismiss(animated: true)
            } else {
              self.navigationController?.popToRootViewController(animated: true)
            }
          }
        }
      case .syncChainDeleteError:
        break
      }
      return .flyDown
    }

    popup.showWithType(showType: .flyUp)
  }

  @objc private func didToggleSyncType(_ toggle: UISwitch) {
    guard let syncDataType = SyncDataTypes(rawValue: toggle.tag) else {
      Logger.module.error("Invalid Sync DataType")
      return
    }

    let toggleExistingStatus = !toggle.isOn

    if syncDataType == .passwords {
      if toggleExistingStatus {
        performSyncDataTypeStatusChange(type: syncDataType)
      } else {
        askForAuthentication(viewType: .sync) { status, error in
          guard status else {
            toggle.setOn(toggleExistingStatus, animated: false)
            return
          }

          toggle.setOn(!toggleExistingStatus, animated: false)
          performSyncDataTypeStatusChange(type: syncDataType)
        }
      }
    } else {
      performSyncDataTypeStatusChange(type: syncDataType)
    }

    func performSyncDataTypeStatusChange(type: SyncDataTypes) {
      switch type {
      case .bookmarks:
        Preferences.Chromium.syncBookmarksEnabled.value = !toggleExistingStatus
      case .history:
        Preferences.Chromium.syncHistoryEnabled.value = !toggleExistingStatus
      case .passwords:
        Preferences.Chromium.syncPasswordsEnabled.value = !toggleExistingStatus
      case .openTabs:
        Preferences.Chromium.syncOpenTabsEnabled.value = !toggleExistingStatus
      }

      syncAPI.enableSyncTypes(syncProfileService: syncProfileService)
    }
  }

  /// Update visibility of view shown when no devices returned for sync session
  /// This view is used for error state and will enable users to fetch details from sync internals
  /// - Parameter isHidden: Boolean to set isHidden
  private func updateNoSyncedDevicesState(isHidden: Bool) {
    if isHidden {
      emptyStateOverlayView.removeFromSuperview()
    } else {
      if emptyStateOverlayView.superview == nil {
        view.addSubview(emptyStateOverlayView)
        view.bringSubviewToFront(emptyStateOverlayView)

        emptyStateOverlayView.snp.makeConstraints {
          $0.edges.equalTo(tableView)
        }
      }
    }
  }

  // MARK: Actions

  @objc
  private func doneTapped() {
    navigationController?.dismiss(animated: true)
  }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

extension SyncSettingsTableViewController {

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    defer { tableView.deselectRow(at: indexPath, animated: true) }

    guard let section = Sections(rawValue: indexPath.section) else {
      return
    }

    if section == .otherActions {
      if indexPath.row == 0 {
        // Sync internals
        let syncInternalsController = ChromeWebUIController(
          braveCore: braveCoreMain,
          isPrivateBrowsing: false
        ).then {
          $0.title = Strings.Sync.internalsTitle
          $0.webView.load(URLRequest(url: URL(string: "brave://sync-internals")!))
        }

        navigationController?.pushViewController(syncInternalsController, animated: true)
      }
      if indexPath.row == 1 {
        // Delete Sync Chain
        presentAlertPopup(for: .syncChainDeleteConfirmation)
      }
      return
    }

    // Device List
    guard section == .deviceList,
      !devices.isEmpty,
      let device = devices[safe: indexPath.row]
    else {
      addAnotherDevice()
      return
    }

    guard device.isCurrentDevice || (!device.isCurrentDevice && device.supportsSelfDelete) else {
      // Devices other than `isCurrentDevice` can only be deleted if
      // `supportsSelfDelete` is true. Attempting to delete another device
      // from the sync chain that does not support it, will crash or
      // have undefined behaviour as the other device won't know that
      // it was deleted.
      return
    }

    let actionSheet = UIAlertController(
      title: device.name,
      message: nil,
      preferredStyle: .actionSheet
    )
    if UIDevice.current.userInterfaceIdiom == .pad {
      let cell = tableView.cellForRow(at: indexPath)
      actionSheet.popoverPresentationController?.sourceView = cell
      actionSheet.popoverPresentationController?.sourceRect = cell?.bounds ?? .zero
      actionSheet.popoverPresentationController?.permittedArrowDirections = [.up, .down]
    }

    let removeAction = UIAlertAction(title: Strings.Sync.removeDeviceAction, style: .destructive) {
      _ in
      if Reachability.shared.status.connectionType == .offline {
        self.present(SyncAlerts.noConnection, animated: true)
        return
      }

      var alertType = AlertActionType.otherDeviceLeft

      if self.devices.count == 1 {
        alertType = .lastDeviceLeft
      } else if device.isCurrentDevice {
        alertType = .currentDeviceLeft
      }

      self.presentAlertPopup(for: alertType, device: device)
    }

    let cancelAction = UIAlertAction(title: Strings.cancelButtonTitle, style: .cancel, handler: nil)

    actionSheet.addAction(removeAction)
    actionSheet.addAction(cancelAction)

    present(actionSheet, animated: true)
  }

  func numberOfSections(in tableView: UITableView) -> Int {
    return Sections.allCases.count
  }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch section {
    case Sections.deviceList.rawValue:
      return devices.count + 1
    case Sections.syncTypes.rawValue:
      return SyncDataTypes.allCases.count
    case Sections.otherActions.rawValue:
      return 2
    default:
      return 0
    }
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    configureCell(cell, atIndexPath: indexPath)

    return cell
  }

  func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    switch section {
    case Sections.deviceList.rawValue:
      return Strings.Sync.devices
    case Sections.syncTypes.rawValue:
      return Strings.Sync.settingsTitle
    default:
      return nil
    }
  }

  func tableView(_ tableView: UITableView, viewForFooterInSection sectionIndex: Int) -> UIView? {
    switch sectionIndex {
    case Sections.syncTypes.rawValue:
      return makeInformationFooterTextView(with: Strings.Sync.configurationInformationText)
    default:
      return nil
    }
  }

  func tableView(_ tableView: UITableView, heightForFooterInSection sectionIndex: Int) -> CGFloat {
    switch sectionIndex {
    case Sections.syncTypes.rawValue:
      return UITableView.automaticDimension
    default:
      return 0
    }
  }

  private func configureCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {
    if devices.isEmpty {
      Logger.module.error("No sync devices to configure.")
      return
    }

    switch indexPath.section {
    case Sections.deviceList.rawValue:
      if indexPath.row == devices.count {
        configureButtonCell(cell, atIndexPath: indexPath)
        return
      }

      guard let device = devices[safe: indexPath.row] else {
        Logger.module.error("Invalid device to configure.")
        return
      }

      guard let name = device.name else { break }
      let deviceName = device.isCurrentDevice ? "\(name) (\(Strings.Sync.thisDevice))" : name

      cell.textLabel?.text = deviceName
      cell.textLabel?.textColor = .braveLabel
    case Sections.otherActions.rawValue:
      configureButtonCell(cell, atIndexPath: indexPath)
    case Sections.syncTypes.rawValue:
      configureToggleCell(cell, for: SyncDataTypes(rawValue: indexPath.row) ?? .bookmarks)
    default:
      Logger.module.error("Section index out of bounds.")
    }
  }

  private func configureButtonCell(_ cell: UITableViewCell, atIndexPath indexPath: IndexPath) {
    cell.accessoryType = .none
    cell.textLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFont.Weight.regular)

    switch indexPath.section {
    case Sections.deviceList.rawValue:
      cell.textLabel?.text = Strings.Sync.addAnotherDevice
      cell.textLabel?.textColor = .braveBlurpleTint
      cell.accessoryType = .disclosureIndicator
    case Sections.otherActions.rawValue:
      if indexPath.row == 0 {
        cell.textLabel?.text = Strings.Sync.internalsTitle
        cell.textLabel?.textColor = .braveBlurpleTint
        cell.accessoryType = .disclosureIndicator
      } else if indexPath.row == 1 {
        cell.textLabel?.text = Strings.Sync.deleteAccount
        cell.textLabel?.textColor = .braveErrorLabel
      }
    default:
      return
    }
  }

  private func configureToggleCell(_ cell: UITableViewCell, for syncType: SyncDataTypes) {
    let toggle = UISwitch().then {
      $0.addTarget(self, action: #selector(didToggleSyncType), for: .valueChanged)
      $0.isOn = isOn(syncType: syncType)
      $0.tag = syncType.rawValue
    }

    cell.do {
      $0.textLabel?.text = syncType.title
      $0.accessoryView = toggle
      $0.selectionStyle = .none
    }

    cell.separatorInset = .zero

    func isOn(syncType: SyncDataTypes) -> Bool {
      switch syncType {
      case .bookmarks:
        return Preferences.Chromium.syncBookmarksEnabled.value
      case .history:
        return Preferences.Chromium.syncHistoryEnabled.value
      case .passwords:
        return Preferences.Chromium.syncPasswordsEnabled.value
      case .openTabs:
        return Preferences.Chromium.syncOpenTabsEnabled.value
      }
    }
  }

  private func makeInformationHeaderTextView(with info: String) -> UITextView {
    return UITextView().then {
      $0.text = info
      $0.textContainerInset = UIEdgeInsets(top: 24, left: 36, bottom: 0, right: 36)
      $0.isEditable = false
      $0.isSelectable = false
      $0.textColor = UIColor(braveSystemName: .textSecondary)
      $0.textAlignment = .natural
      $0.font = UIFont.preferredFont(forTextStyle: .subheadline)
      $0.isScrollEnabled = false
      $0.backgroundColor = .clear
    }
  }

  private func makeInformationFooterTextView(with info: String) -> UITextView {
    return UITextView().then {
      $0.text = info
      $0.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
      $0.isEditable = false
      $0.isSelectable = false
      $0.textColor = UIColor(braveSystemName: .textSecondary)
      $0.textAlignment = .natural
      $0.font = UIFont.preferredFont(forTextStyle: .footnote)
      $0.isScrollEnabled = false
      $0.backgroundColor = .clear
    }
  }
}

// MARK: - Sync Device Functionality

extension SyncSettingsTableViewController {

  private func updateDeviceList() {
    if let json = syncAPI.getDeviceListJSON(), let data = json.data(using: .utf8) {
      do {
        let devices = try JSONDecoder().decode([BraveSyncDevice].self, from: data)
        self.devices = devices

        if devices.count <= 0 {
          self.updateNoSyncedDevicesState(isHidden: false)
        } else {
          self.tableView.reloadData()
        }
      } catch {
        Logger.module.error("\(error.localizedDescription)")
      }
    } else {
      Logger.module.error("Something went wrong while retrieving Sync Devices..")
    }
  }

  private func addAnotherDevice() {
    askForAuthentication(viewType: .sync) { [weak self] status, error in
      guard let self = self, status else { return }

      let view = SyncSelectDeviceTypeViewController()

      view.syncInitHandler = { title, type in
        let view = SyncAddDeviceViewController(title: title, type: type, syncAPI: self.syncAPI)
        view.addDeviceHandler = {
          self.navigationController?.popToViewController(self, animated: true)
        }
        self.navigationController?.pushViewController(view, animated: true)
      }

      self.navigationController?.pushViewController(view, animated: true)
    }
  }
}

// MARK: NavigationPrevention

extension SyncSettingsTableViewController: NavigationPrevention {
  func enableNavigationPrevention() {
    loadingView.isHidden = false
    navigationItem.rightBarButtonItem?.isEnabled = false
    navigationItem.hidesBackButton = true
  }

  func disableNavigationPrevention() {
    loadingView.isHidden = true
    navigationItem.rightBarButtonItem?.isEnabled = true
    navigationItem.hidesBackButton = false
  }
}
