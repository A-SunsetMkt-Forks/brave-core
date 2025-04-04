import BraveShared
import CertificateUtilities
import Foundation
import Shared
import Storage
import Web
import WebKit

struct ErrorPageModel {
  let requestURL: URL
  let originalURL: URL
  let components: URLComponents
  let errorCode: Int
  let description: String
  let originalHost: String
  let domain: String
  let error: NSError

  init?(request: URLRequest) {
    guard let requestUrl = request.url,
      let originalUrl = InternalURL(requestUrl)?.originalURLFromErrorPage
    else {
      return nil
    }

    guard let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
      let code = components.valueForQuery("code"),
      let errCode = Int(code),
      let errDescription = components.valueForQuery("description"),
      let errURLDomain = originalUrl.host,
      let errDomain = components.valueForQuery("domain")
    else {
      return nil
    }

    self.requestURL = requestUrl
    self.originalURL = originalUrl
    self.components = components
    self.errorCode = errCode
    self.description = errDescription
    self.originalHost = errURLDomain
    self.domain = errDomain

    var userInfo: [String: Any] = [
      NSLocalizedDescriptionKey: errDescription
    ]

    if let encodedCertificate = components.valueForQuery("certerror") {
      userInfo["NSErrorPeerCertificateChainKey"] = encodedCertificate
    }

    self.error = NSError(domain: errDomain, code: errCode, userInfo: userInfo)
  }
}

public class ErrorPageHandler: InternalSchemeResponse {
  public static let path = InternalURL.Path.errorpage.rawValue

  private let errorHandlers: [InterstitialPageHandler] = [
    CertificateErrorPageHandler(),
    NetworkErrorPageHandler(),
    GenericErrorPageHandler(),
  ]

  public func response(forRequest request: URLRequest) async -> (URLResponse, Data)? {
    guard let model = ErrorPageModel(request: request) else {
      return nil
    }
    return await errorHandlers.filter({ $0.canHandle(error: model.error) }).first?.response(
      for: model
    )
  }

  public init() {}
}

class ErrorPageHelper {

  fileprivate weak var certStore: CertStore?

  init(certStore: CertStore?) {
    self.certStore = certStore
  }

  func loadPage(_ error: NSError, forUrl url: URL, inTab tab: some TabState) {
    guard var components = URLComponents(string: "\(InternalURL.baseUrl)/\(ErrorPageHandler.path)")
    else {
      return
    }

    // Page has failed to load again, just return and keep showing the existing error page.
    if let internalUrl = InternalURL(url), internalUrl.originalURLFromErrorPage == url {
      return
    }

    var queryItems = [
      URLQueryItem(name: InternalURL.Param.url.rawValue, value: url.absoluteString),
      URLQueryItem(name: "code", value: String(error.code)),
      URLQueryItem(name: "domain", value: error.domain),
      URLQueryItem(name: "description", value: error.localizedDescription),
      // 'timestamp' is used for the js reload logic
      URLQueryItem(name: "timestamp", value: "\(Int(Date().timeIntervalSince1970 * 1000))"),
    ]

    // If this is an invalid certificate, show a certificate error allowing the
    // user to go back or continue. The certificate itself is encoded and added as
    // a query parameter to the error page URL; we then read the certificate from
    // the URL if the user wants to continue.
    if CertificateErrorPageHandler.isValidCertificateError(error: error),
      let certChain = error.userInfo["NSErrorPeerCertificateChainKey"] as? [SecCertificate],
      let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
      let certErrorCode = underlyingError.userInfo["_kCFStreamErrorCodeKey"] as? Int
    {
      let encodedCerts = ErrorPageHelper.encodeCertChain(certChain)
      queryItems.append(URLQueryItem(name: "badcerts", value: encodedCerts))

      let certError = SecurityCertErrors[OSStatus(certErrorCode)] ?? ""
      queryItems.append(URLQueryItem(name: "certerror", value: String(certError)))
    }

    components.queryItems = queryItems
    if let urlWithQuery = components.url {
      // A new page needs to be added to the history stack (i.e. the simple case of trying to navigate to an url for the first time and it fails, without pushing a page on the history stack, the webview will just show the current page).
      tab.loadRequest(PrivilegedRequest(url: urlWithQuery) as URLRequest)
    }
  }
}

extension ErrorPageHelper {
  static func errorCode(for url: URL) -> Int {
    // ErrorCode is zero if there's no error.
    // Non-Zero (negative or positive) when there is an error

    if InternalURL.isValid(url: url),
      let internalUrl = InternalURL(url),
      internalUrl.isErrorPage
    {

      let query = url.getQuery()
      guard let code = query["code"],
        let errCode = Int(code)
      else {
        return 0
      }

      return errCode
    }
    return 0
  }

  static func certificateError(for url: URL) -> Int {
    let errCode = errorCode(for: url)

    // ErrorCode is zero if there's no error.
    // Non-Zero (negative or positive) when there is an error
    if errCode != 0 {
      if let code = CFNetworkErrors(rawValue: Int32(errCode)),
        CFNetworkErrors.certErrors.contains(code)
      {
        return errCode
      }

      if NSURLCertErrors.contains(errCode) {
        return errCode
      }

      if SecurityCertErrors[OSStatus(errCode)] != nil {
        return errCode
      }
      return 0
    }
    return 0
  }

  static func hasCertificates(for url: URL) -> Bool {
    return (url as NSURL).valueForQueryParameter(key: "badcerts") != nil
  }

  static func serverTrust(from errorURL: URL) throws -> SecTrust? {
    guard let internalUrl = InternalURL(errorURL),
      internalUrl.isErrorPage,
      let originalURL = internalUrl.originalURLFromErrorPage
    else {
      return nil
    }

    guard let certs = CertificateErrorPageHandler.certsFromErrorURL(errorURL),
      !certs.isEmpty,
      let host = originalURL.host
    else {
      return nil
    }

    return try BraveCertificateUtils.createServerTrust(certs, for: host)
  }

  private static func encodeCertChain(_ certificates: [SecCertificate]) -> String {
    let certs = certificates.map({
      (SecCertificateCopyData($0) as Data).base64EncodedString
    })

    return certs.joined(separator: ",")
  }

  func addCertificate(_ cert: SecCertificate, forOrigin origin: String) {
    certStore?.addCertificate(cert, forOrigin: origin)
  }
}
