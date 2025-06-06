// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveShared
import Collections
import Combine
import Data
import Shared
import Web
import WebKit
import os.log

private let log = ContentBlockerManager.log

struct ContentBlockingConfig {
  struct Prefs {
    static let normalBrowsingEnabledKey = "prefkey.trackingprotection.normalbrowsing"
    static let privateBrowsingEnabledKey = "prefkey.trackingprotection.privatebrowsing"
  }

  struct Defaults {
    static let normalBrowsing = true
    static let privateBrowsing = true
  }
}

struct NoImageModeDefaults {
  static let script =
    "[{'trigger':{'url-filter':'.*','resource-type':['image']},'action':{'type':'block'}}]"
    .replacingOccurrences(of: "'", with: "\"")
  static let scriptName = "images"
}

enum BlockingStrength: String {
  case basic
  case strict

  static let allOptions: [BlockingStrength] = [.basic, .strict]
}

struct BlockedRequestInfo: Hashable, Identifiable {
  enum Location: String {
    case contentBlocker
    case requestBlocking

    var display: String {
      switch self {
      case .contentBlocker:
        return Strings.Shields.contentBlocker
      case .requestBlocking:
        return Strings.Shields.requestBlocking
      }
    }
  }
  let requestURL: URL
  let sourceURL: URL
  let resourceType: AdblockEngine.ResourceType
  let isAggressive: Bool
  let location: Location

  var id: String {
    "\(requestURL)\(sourceURL)\(resourceType.rawValue)\(isAggressive)\(location.rawValue)"
  }
}

class ContentBlockerHelper: ObservableObject {
  private(set) weak var tab: (any TabState)?

  /// The rule lists that are loaded into the current tab
  private var setRuleLists: Set<WKContentRuleList> = []

  var stats: TPPageStats = TPPageStats() {
    didSet {
      guard let tab = self.tab else { return }
      statsDidChange?(stats)
    }
  }

  var statsDidChange: ((TPPageStats) -> Void)?
  @Published var blockedRequests: OrderedSet<BlockedRequestInfo> = []
  /// Cached standard selectors. Key is the URL's `baseDomain`.
  private var hiddenStandardSelectors: [String: Set<String>] = [:]
  /// Cached aggressive selectors. Key is the URL's `baseDomain`.
  private var hiddenAggressiveSelectors: [String: Set<String>] = [:]

  init(tab: (any TabState)?) {
    self.tab = tab
  }

  @MainActor func set(ruleLists: Set<WKContentRuleList>) {
    guard ruleLists != setRuleLists else { return }
    var addedIds: [String] = []
    var removedIds: [String] = []

    // Remove unwanted rule lists
    for ruleList in setRuleLists.subtracting(ruleLists) {
      // It's added but we don't want it. So we remove it.
      tab?.configuration.userContentController.remove(ruleList)
      setRuleLists.remove(ruleList)
      removedIds.append(ruleList.identifier)
    }

    // Add missing rule lists
    for ruleList in ruleLists.subtracting(setRuleLists) {
      tab?.configuration.userContentController.add(ruleList)
      setRuleLists.insert(ruleList)
      addedIds.append(ruleList.identifier)
    }

    let parts = [
      addedIds.sorted(by: { $0 < $1 }).map({ " + \($0)" }).joined(separator: "\n"),
      removedIds.sorted(by: { $0 < $1 }).map({ " - \($0)" }).joined(separator: "\n"),
    ]

    ContentBlockerManager.log.debug("Set rule lists:\n\(parts.joined(separator: "\n"))")
  }

  func resetSelectorsCache() {
    hiddenStandardSelectors.removeAll()
    hiddenAggressiveSelectors.removeAll()
  }

  /// Get the cached selectors for the given URL.
  func cachedSelectors(for url: URL) -> (standard: Set<String>, aggressive: Set<String>)? {
    guard let baseDomain = url.baseDomain else {
      return nil
    }
    return (hiddenStandardSelectors[baseDomain] ?? [], hiddenAggressiveSelectors[baseDomain] ?? [])
  }

  /// Cache the given selectors for the given URL.
  func cacheSelectors(
    for url: URL,
    standardSelectors: Set<String>,
    aggressiveSelectors: Set<String>
  ) {
    guard let baseDomain = url.baseDomain else {
      return
    }
    var cachedStandardSelectors = hiddenStandardSelectors[baseDomain] ?? .init()
    cachedStandardSelectors.formUnion(standardSelectors)
    var cachedAggressiveSelectors = hiddenAggressiveSelectors[baseDomain] ?? .init()
    cachedAggressiveSelectors.formUnion(aggressiveSelectors)
    hiddenStandardSelectors[baseDomain] = cachedStandardSelectors
    hiddenAggressiveSelectors[baseDomain] = cachedAggressiveSelectors
  }
}
