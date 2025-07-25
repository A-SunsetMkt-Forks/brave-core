// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import Storage
import XCTest

@testable import Brave

open class MockProfile: Profile {
  init() {}

  lazy public var certStore: CertStore = {
    return CertStore()
  }()

  lazy public var searchEngines: SearchEngines = {
    return SearchEngines()
  }()
}
