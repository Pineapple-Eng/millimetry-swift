import Foundation
import Testing
@testable import Millimetry

struct UploadOutcomeTests {
    private func response(_ status: Int, _ body: String = "{}", headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test func classifiesEachDocumentedStatus() {
        #expect(UploadOutcome.classify(response(200, #"{"accepted":3,"dropped":0}"#)) == .delivered)
        #expect(UploadOutcome.classify(response(200, #"{"accepted":0,"dropped":3,"reason":"over_quota"}"#)) == .overQuota)
        #expect(UploadOutcome.classify(response(400)) == .rejected(status: 400))
        #expect(UploadOutcome.classify(response(401)) == .rejected(status: 401))
        #expect(UploadOutcome.classify(response(403)) == .rejected(status: 403))
        #expect(UploadOutcome.classify(response(413)) == .tooLarge)
        #expect(UploadOutcome.classify(response(429, headers: ["retry-after": "7"])) == .rateLimited(retryAfter: 7))
        #expect(UploadOutcome.classify(response(429)) == .rateLimited(retryAfter: 60))
        #expect(UploadOutcome.classify(response(500)) == .retryLater)
        #expect(UploadOutcome.classify(response(503, headers: ["retry-after": "5"])) == .retryLater)
    }
}
