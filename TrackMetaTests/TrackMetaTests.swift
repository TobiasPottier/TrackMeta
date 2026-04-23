//
//  TrackMetaTests.swift
//  TrackMetaTests
//
//  Created by Tobias Pottier on 20/04/2026.
//

import Foundation
import Testing
@testable import TrackMeta

struct TrackMetaTests {

    @Test func http429ReturnsCappedSnapshotWithHeaderUsage() async throws {
        let reset = Date().addingTimeInterval(900).timeIntervalSince1970
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: [
                    "anthropic-ratelimit-unified-5h-utilization": "0.42",
                    "anthropic-ratelimit-unified-7d-utilization": "0.17",
                    "anthropic-ratelimit-unified-5h-reset": "\(reset)",
                    "anthropic-ratelimit-unified-7d-reset": "\(reset)"
                ]
            )!
            return (response, Data())
        }

        let client = ClaudeUsageClient(session: Self.mockSession())

        let snapshot = try await client.fetchSnapshot(accessToken: "token")

        #expect(snapshot.isUsageCapReached)
        #expect(snapshot.fiveHour.percent == 42)
        #expect(snapshot.sevenDay.percent == 17)
        #expect(snapshot.fiveHour.resetsAt != nil)
        #expect(snapshot.sevenDay.resetsAt != nil)
    }

    @Test func http439ReturnsCappedSnapshotWithPriorUsageWhenHeadersAreMissing() async throws {
        let reset = Date().addingTimeInterval(900).timeIntervalSince1970
        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 439,
                httpVersion: nil,
                headerFields: [
                    "anthropic-ratelimit-unified-5h-reset": "\(reset)",
                    "anthropic-ratelimit-unified-7d-reset": "\(reset)"
                ]
            )!
            return (response, Data())
        }

        let prior = UsageSnapshot(
            fiveHour: UsageBucket(used: 58, limit: 100, resetsAt: Date().addingTimeInterval(300)),
            sevenDay: UsageBucket(used: 21, limit: 100, resetsAt: Date().addingTimeInterval(600)),
            fetchedAt: Date().addingTimeInterval(-60),
            isUsageCapReached: false
        )
        let client = ClaudeUsageClient(session: Self.mockSession())

        let snapshot = try await client.fetchSnapshot(accessToken: "token", preservingUsageFrom: prior)

        #expect(snapshot.isUsageCapReached)
        #expect(snapshot.fiveHour.percent == 58)
        #expect(snapshot.sevenDay.percent == 21)
        #expect(snapshot.fiveHour.resetsAt != nil)
        #expect(snapshot.sevenDay.resetsAt != nil)
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
