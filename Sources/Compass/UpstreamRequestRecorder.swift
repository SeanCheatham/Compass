import Foundation
import OpenAI

/// Captures the most-recent outbound chat-completions `URLRequest` so the
/// executor can replay it after an upstream 4xx/5xx error to fetch the
/// response body. MacPaw's `StreamingSession` cancels the URLSession data
/// task as soon as it sees `statusCode >= 400`, so the body is never read
/// and `OpenAIError.statusError` carries only the `HTTPURLResponse`. Without
/// the body we can't see what the provider actually objected to, which is
/// the difference between a useful error and the opaque
/// "statusError(... statusCode: 400)" the user sees in the live log today.
final class UpstreamRequestRecorder: OpenAIMiddleware, @unchecked Sendable {
  private let lock = NSLock()
  private var _lastRequest: URLRequest?

  /// The last URLRequest the middleware saw on `intercept(request:)`.
  /// Nil before any request has been issued. Reads are synchronised so the
  /// executor (running on a Task) can read while the lib's serial queue
  /// writes from `intercept`.
  var lastRequest: URLRequest? {
    lock.lock()
    defer { lock.unlock() }
    return _lastRequest
  }

  func intercept(request: URLRequest) -> URLRequest {
    lock.lock()
    _lastRequest = request
    lock.unlock()
    return request
  }
}
