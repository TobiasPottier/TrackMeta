//
//  TrackMetaTests.swift
//  TrackMetaTests
//
//  Created by Tobias Pottier on 20/04/2026.
//

import Foundation
import Testing
@testable import TrackMeta

// Serialized: the HTTP tests share `MockURLProtocol.requestHandler` (a global
// static), so parallel execution lets them clobber each other's handler.
@Suite(.serialized)
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
        // `percent` is a Double from integer division (used/limit*100), so it
        // carries floating-point fuzz. Compare it the way the app renders it.
        #expect(Int(snapshot.fiveHour.percent.rounded()) == 42)
        #expect(Int(snapshot.sevenDay.percent.rounded()) == 17)
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
        #expect(Int(snapshot.fiveHour.percent.rounded()) == 58)
        #expect(Int(snapshot.sevenDay.percent.rounded()) == 21)
        #expect(snapshot.fiveHour.resetsAt != nil)
        #expect(snapshot.sevenDay.resetsAt != nil)
    }

    @Test func sessionHistoryAddsToolEventWhenOnlyTargetChanges() {
        let now = Date()
        let initialSession = Self.session(lastTool: "Read", lastToolTarget: "/tmp/one.swift")
        let updatedSession = Self.session(lastTool: "Read", lastToolTarget: "/tmp/two.swift")

        let history = SessionHistoryIngestion.initial(from: initialSession, at: now)
        let updated = SessionHistoryIngestion.update(
            history,
            with: updatedSession,
            at: now.addingTimeInterval(5)
        )

        #expect(updated.lastTool == "Read")
        #expect(updated.lastToolTarget == "/tmp/two.swift")
        #expect(updated.events.count == history.events.count + 1)

        guard case .toolChanged(let tool, let target) = updated.events.last?.kind else {
            Issue.record("Expected a toolChanged event")
            return
        }

        #expect(tool == "Read")
        #expect(target == "/tmp/two.swift")
    }

    // MARK: - Usage forecast

    @Test func forecastReportsEtaWhenSustainedPaceReachesCap() {
        let start = Date()
        let samples = [
            Self.sample(0, 0, start: start),
            Self.sample(3600, 20, start: start),
            Self.sample(7200, 40, start: start)
        ]
        let forecast = linearUsageForecast(
            samples: samples,
            valueFor: { $0.fiveHourPercent },
            currentTime: start.addingTimeInterval(7200),
            currentValue: 40,
            until: start.addingTimeInterval(SessionWindow.fiveHourSeconds)
        )
        guard let forecast else { Issue.record("Expected a forecast"); return }
        // 40% now climbing +20%/h reaches 100% exactly at the 5h reset.
        #expect(forecast.endValue == 100)
        #expect(abs(forecast.endTime.timeIntervalSince(start) - SessionWindow.fiveHourSeconds) < 1)
    }

    @Test func forecastReportsProjectedEndValueWhenBelowCap() {
        let start = Date()
        let end = start.addingTimeInterval(SessionWindow.fiveHourSeconds)
        let samples = [
            Self.sample(0, 0, start: start),
            Self.sample(3600, 5, start: start),
            Self.sample(7200, 10, start: start)
        ]
        let forecast = linearUsageForecast(
            samples: samples,
            valueFor: { $0.fiveHourPercent },
            currentTime: start.addingTimeInterval(7200),
            currentValue: 10,
            until: end
        )
        guard let forecast else { Issue.record("Expected a forecast"); return }
        // 10% now climbing +5%/h over the remaining 3h projects to ~25% by reset.
        #expect(forecast.endTime == end)
        #expect(Int(forecast.endValue.rounded()) == 25)
    }

    // Regression: a short flat stretch — an idle pause, or the gap around an app
    // relaunch — used to collapse the recency-weighted slope and erase the ETA.
    // The average-pace fit keeps the projection grounded in the whole window.
    @Test func forecastSurvivesShortFlatTailFromPauseOrRelaunch() {
        let start = Date()
        let withPause = [
            Self.sample(0, 0, start: start),
            Self.sample(3600, 30, start: start),
            Self.sample(7200, 60, start: start),
            Self.sample(7800, 60, start: start)   // 10 minutes flat
        ]
        let forecast = linearUsageForecast(
            samples: withPause,
            valueFor: { $0.fiveHourPercent },
            currentTime: start.addingTimeInterval(7800),
            currentValue: 60,
            until: start.addingTimeInterval(SessionWindow.fiveHourSeconds)
        )
        guard let forecast else { Issue.record("Expected a forecast"); return }
        #expect(forecast.endValue == 100)
        #expect(forecast.endTime < start.addingTimeInterval(SessionWindow.fiveHourSeconds))
    }

    @Test func forecastNeedsAtLeastTwoSamples() {
        let start = Date()
        let forecast = linearUsageForecast(
            samples: [Self.sample(0, 10, start: start)],
            valueFor: { $0.fiveHourPercent },
            currentTime: start,
            currentValue: 10,
            until: start.addingTimeInterval(SessionWindow.fiveHourSeconds)
        )
        #expect(forecast == nil)
    }

    private static func sample(_ secondsFromStart: TimeInterval, _ percent: Double, start: Date) -> UsageSample {
        UsageSample(timestamp: start.addingTimeInterval(secondsFromStart), fiveHourPercent: percent, sevenDayPercent: 0)
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func session(
        status: ClaudeSession.Status = .working,
        lastTool: String? = nil,
        lastToolTarget: String? = nil
    ) -> ClaudeSession {
        ClaudeSession(
            sessionId: UUID().uuidString,
            status: status,
            lastTool: lastTool,
            lastToolTarget: lastToolTarget,
            cwd: "/tmp/project",
            summary: "Session",
            idleForSeconds: 0,
            contextPercentage: nil
        )
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
