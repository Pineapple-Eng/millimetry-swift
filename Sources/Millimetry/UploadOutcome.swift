import Foundation

/// What a response means for the batch that was sent.
enum UploadOutcome: Equatable {
    /// 200: stored (or already stored). Delete the batch.
    case delivered
    /// 200 with `"reason": "over_quota"`: the plan limit is used up. Delete the batch.
    case overQuota
    /// 413: split in half and retry; a single event that is still too large is dropped.
    case tooLarge
    /// 429: keep the batch and wait this many seconds.
    case rateLimited(retryAfter: TimeInterval)
    /// A network error, 5xx or 503: keep the batch and back off.
    case retryLater
    /// 400, 401 or any other 4xx: it will never succeed. Delete the batch.
    case rejected(status: Int)

    static func classify(_ response: HTTPResponse) -> UploadOutcome {
        switch response.status {
        case 200...299:
            if let body = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
               body["reason"] as? String == "over_quota" {
                return .overQuota
            }
            return .delivered
        case 413:
            return .tooLarge
        case 429:
            let seconds = response.headers["retry-after"].flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfter: seconds ?? 60)
        case 500...599:
            return .retryLater
        case 400...499:
            return .rejected(status: response.status)
        default:
            return .retryLater
        }
    }
}
