// Copyright 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Foundation
import Preferences
import Shared
import SwiftUI
import WebKit

public enum AIChatModelKey: String {
  case chatBasic = "chat-basic"
  case chatQwen = "chat-qwen"
  case chatClaudeHaiku = "chat-claude-haiku"
  case chatClaudeSonnet = "chat-claude-sonnet"
  case chatDeepseekR1 = "chat-deepseek-r1"
}

public protocol AIChatWebDelegate: AnyObject {
  var title: String? { get }
  var url: URL? { get }
  var isLoading: Bool { get }

  @MainActor
  func getPageContentType() async -> String?

  @MainActor
  func getMainArticle() async -> String?

  @MainActor
  func getPDFDocument() async -> String?

  @MainActor
  func getPrintViewPDF() async -> Data?
}

public class AIChatViewModel: NSObject, ObservableObject {
  // TODO(petemill): AIChatService, ConversationHandler refs should
  // be passed directly to this object instead of proxied through the
  // AIChat class.
  private var api: AIChat!
  private weak var webDelegate: AIChatWebDelegate?
  private let braveTalkScript: AIChatBraveTalkJavascript?
  var querySubmited: String?

  @Published var siteInfo: [AiChat.AssociatedContent] = []
  @Published var _shouldSendPageContents: Bool = true
  @Published var _canShowPremiumPrompt: Bool = false
  @Published var premiumStatus: AiChat.PremiumStatus = .inactive
  @Published var suggestedQuestions: [String] = []
  @Published var suggestionsStatus: AiChat.SuggestionGenerationStatus = .none
  @Published var conversationHistory: [AiChat.ConversationTurn] = []
  @Published var models: [AiChat.Model] = []
  @Published var currentModel: AiChat.Model?

  @Published var requestInProgress: Bool = false
  @Published var apiError: AiChat.APIError = .none

  public var slashActions: [AiChat.ActionGroup] {
    return api.slashActions
  }

  public var isCurrentModelPremium: Bool {
    guard let currentModel = currentModel else { return false }

    return currentModel.options.tag == .leoModelOptions
      && currentModel.options.leoModelOptions?.access == .premium
  }

  public var isContentAssociationPossible: Bool {
    return webDelegate?.url?.isWebPage(includeDataURIs: true) == true
  }

  public var shouldSendPageContents: Bool {
    get {
      return _shouldSendPageContents
    }

    set {
      objectWillChange.send()
      api.setShouldSendPageContents(newValue)
    }
  }

  public var shouldShowPremiumPrompt: Bool {
    get {
      return _canShowPremiumPrompt
    }

    set {  // swiftlint:disable:this unused_setter_value
      _canShowPremiumPrompt = newValue
      if !newValue {
        api.dismissPremiumPrompt()
      }
    }
  }

  public var shouldShowTermsAndConditions: Bool {
    !self.conversationHistory.isEmpty && !api.isAgreementAccepted
  }

  public var shouldShowSuggestions: Bool {
    self.apiError == .none && api.isAgreementAccepted && self.shouldSendPageContents
      && (!self.suggestedQuestions.isEmpty || self.suggestionsStatus == .canGenerate
        || self.suggestionsStatus == .isGenerating)
  }

  public var shouldShowGenerateSuggestionsButton: Bool {
    self.suggestionsStatus == .canGenerate || self.suggestionsStatus == .isGenerating
  }

  public var isAgreementAccepted: Bool {
    get {
      return api.isAgreementAccepted
    }

    set {
      objectWillChange.send()
      api.isAgreementAccepted = newValue
    }
  }

  public var defaultAIModelKey: String {
    get {
      return api.defaultModelKey
    }

    set {
      objectWillChange.send()
      api.defaultModelKey = newValue
    }
  }

  public init(
    braveCore: BraveProfileController,
    webDelegate: AIChatWebDelegate?,
    braveTalkScript: AIChatBraveTalkJavascript?,
    querySubmited: String? = nil
  ) {
    self.webDelegate = webDelegate
    self.braveTalkScript = braveTalkScript
    self.querySubmited = querySubmited

    super.init()

    // Initialize
    api = braveCore.aiChatAPI(with: self)
  }

  // MARK: - API

  func changeModel(modelKey: String) {
    api.changeModel(modelKey)
  }

  func generateSuggestions() {
    if self.suggestionsStatus != .isGenerating && self.suggestionsStatus != .hasGenerated {
      objectWillChange.send()
      api.generateQuestions()
    }
  }

  func summarizePage() {
    api.submitSummarizationRequest()
  }

  func submitSuggestion(_ suggestion: String) {
    apiError = .none
    api.submitSuggestion(suggestion)
  }

  func submitQuery(_ text: String) {
    apiError = .none
    api.submitHumanConversationEntry(text)
  }

  func submitSelectedText(_ text: String, action: AiChat.ActionType) {
    apiError = .none
    api.submitSelectedText(text, actionType: action)
  }

  func retryLastRequest() {
    if !self.conversationHistory.isEmpty {
      api.retryAPIRequest()
    }
  }

  @MainActor
  func clearConversationHistory() async {
    api.createNewConversation()
    await self.getInitialState()
  }

  @MainActor
  func clearAndResetData() async {
    await self.clearConversationHistory()
    api.isAgreementAccepted = false
  }

  @MainActor
  func refreshPremiumStatus() async {
    self.premiumStatus = await api.premiumStatus()
  }

  @MainActor
  func getInitialState() async {
    let state = await api.state()
    self.requestInProgress = state.isRequestInProgress
    self.suggestedQuestions = state.suggestedQuestions
    self.suggestionsStatus = state.suggestionStatus
    self.siteInfo = state.associatedContent
    self._shouldSendPageContents = state.associatedContent.count == 1
    self.apiError = state.error
    self.models = state.allModels

    self.currentModel = self.models.first(where: { $0.key == state.currentModelKey })
    self.conversationHistory = api.conversationHistory
  }

  @MainActor
  func clearErrorAndGetFailedMessage() async -> AiChat.ConversationTurn? {
    return await api.clearErrorAndGetFailedMessage()
  }

  @MainActor
  func rateConversation(isLiked: Bool, turnId: String) async -> String? {
    return await api.rateMessage(isLiked, turnId: turnId)
  }

  @MainActor
  func submitFeedback(category: String, feedback: String, ratingId: String) async -> Bool {
    // TODO: Add UI for `sendPageURL`
    return await api.sendFeedback(
      category,
      feedback: feedback,
      ratingId: ratingId,
      sendPageUrl: false
    )
  }

  @MainActor
  func modifyConversation(turnId: String, newText: String) {
    api.modifyConversation(turnId, newText: newText)
  }
}

extension AIChatViewModel: AIChatDelegate {
  public func getPageTitle() -> String? {
    // Return the Page Title
    if let title = webDelegate?.title, !title.isEmpty {
      return title
    }

    guard let url = getLastCommittedURL() else {
      return nil
    }

    // Return the URL domain/host
    if url.pathExtension.isEmpty {
      return URLFormatter.formatURLOrigin(
        forDisplayOmitSchemePathAndTrivialSubdomains: url.absoluteString
      )
    }

    // Return the file name with extension
    return url.lastPathComponent
  }

  public func getLastCommittedURL() -> URL? {
    if let url = webDelegate?.url {
      return InternalURL.isValid(url: url) ? nil : url
    }
    return nil
  }

  @MainActor
  public func pageContent() async -> (String?, Bool) {
    guard let webDelegate else {
      return (nil, false)
    }

    if let transcript = await braveTalkScript?.getTranscript() {
      return (transcript, false)
    }

    if await webDelegate.getPageContentType() == "application/pdf" {
      if let base64EncodedPDF = await webDelegate.getPDFDocument() {
        return (await AIChatPDFRecognition.parse(pdfData: base64EncodedPDF), false)
      }

      // Attempt to parse the page as a PDF/Image
      guard let pdfData = await webDelegate.getPrintViewPDF() else {
        return (nil, false)
      }
      return (await AIChatPDFRecognition.parseToImage(pdfData: pdfData), false)
    }

    // Fetch regular page content
    let text = await webDelegate.getMainArticle()
    if let text = text, !text.isEmpty {
      return (text, false)
    }

    // No article text. Attempt to parse the page as a PDF/Image
    guard let pdfData = await webDelegate.getPrintViewPDF() else {
      return (nil, false)
    }
    return (await AIChatPDFRecognition.parseToImage(pdfData: pdfData), false)
  }

  public func isDocumentOnLoadCompletedInPrimaryFrame() -> Bool {
    return webDelegate?.isLoading == false
  }

  public func onHistoryUpdate() {
    self.conversationHistory = api.conversationHistory
  }

  public func onAPIRequest(inProgress: Bool) {
    self.requestInProgress = inProgress
  }

  public func onAPIResponseError(_ error: AiChat.APIError) {
    self.apiError = error
  }

  public func onSuggestedQuestionsChanged(
    _ questions: [String],
    status: AiChat.SuggestionGenerationStatus
  ) {
    self.suggestedQuestions = questions
    self.suggestionsStatus = status
  }

  public func onModelChanged(_ modelKey: String, modelList: [AiChat.Model]) {
    self.currentModel = self.models.first(where: { $0.key == modelKey })
    self.models = modelList
  }

  public func onPageHasContent(
    _ siteInfo: [AiChat.AssociatedContent]
  ) {
    self.siteInfo = siteInfo
    self._shouldSendPageContents = siteInfo.count == 1
  }

  public func onServiceStateChanged(_ state: AiChat.ServiceState) {
    self._canShowPremiumPrompt = state.canShowPremiumPrompt
  }
}

extension AiChat.Model {
  var introMessage: String {
    guard let modelKey = AIChatModelKey(rawValue: self.key) else {
      return String(format: Strings.AIChat.introMessageGenericMessageDescription, self.displayName)
    }

    switch modelKey {
    case .chatBasic:
      return Strings.AIChat.introMessageLlamaMessageDescription

    case .chatQwen:
      return Strings.AIChat.introMessageQwenMessageDescription

    case .chatClaudeHaiku:
      return Strings.AIChat.introMessageClaudeHaikuMessageDescription

    case .chatClaudeSonnet:
      return Strings.AIChat.introMessageClaudeSonnetMessageDescription

    case .chatDeepseekR1:
      return Strings.AIChat.introMessageDeepSeekR1MessageDescription
    }
  }

  var purposeDescription: String {
    guard let modelKey = AIChatModelKey(rawValue: self.key) else {
      return self.displayName
    }

    switch modelKey {
    case .chatBasic:
      return Strings.AIChat.introMessageLlamaModelPurposeDescription

    case .chatQwen:
      return Strings.AIChat.introMessageQwenModelPurposeDescription

    case .chatClaudeHaiku:
      return Strings.AIChat.introMessageClaudeHaikuModelPurposeDescription

    case .chatClaudeSonnet:
      return Strings.AIChat.introMessageClaudeSonnetModelPurposeDescription

    case .chatDeepseekR1:
      return Strings.AIChat.introMessageDeepSeekR1ModelPurposeDescription
    }
  }
}
