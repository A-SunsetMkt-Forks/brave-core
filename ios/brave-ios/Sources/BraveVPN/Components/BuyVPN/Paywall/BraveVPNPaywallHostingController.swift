// Copyright 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

public class BraveVPNPaywallHostingController: UIHostingController<BraveVPNPaywallView> {

  public init(paywallView: BraveVPNPaywallView) {
    super.init(rootView: paywallView)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    navigationItem.do {
      let appearance = UINavigationBarAppearance().then {
        $0.configureWithDefaultBackground()
        $0.backgroundColor = UIColor(braveSystemName: .primitivePrimary10)
        $0.titleTextAttributes = [.foregroundColor: UIColor.white]
        $0.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
      }
      $0.standardAppearance = appearance
      $0.scrollEdgeAppearance = appearance

      $0.rightBarButtonItem = UIBarButtonItem(
        title: Strings.VPN.restorePurchases,
        style: .plain,
        target: self,
        action: #selector(tappedRestore)
      )

      $0.leftBarButtonItem = UIBarButtonItem(
        title: Strings.CancelString,
        style: .plain,
        target: self,
        action: #selector(tappedCancel)
      )
    }

    navigationController?.navigationBar.tintColor = .white
  }

  // MARK: Actions

  @objc private func tappedRestore() {
    rootView.restorePurchase()
  }

  @objc private func tappedCancel() {
    dismiss(animated: true)
  }
}
