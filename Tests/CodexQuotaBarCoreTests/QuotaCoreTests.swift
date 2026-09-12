import Foundation
import Testing
@testable import CodexQuotaBarCore

@Suite("Quota core")
struct QuotaCoreTests {
    @Test("A weekly primary is not reused as a five-hour window")
    func partialWindow() throws {
        let data = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080}}}}"#.utf8)
        let snapshot = try RateLimitParser.parseResponse(data)
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.weekly?.remainingPercent == 80)
    }

    @Test("Windows without durations retain positional compatibility")
    func legacyWindows() throws {
        let data = Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":20},"secondary":{"usedPercent":30}}}}"#.utf8)
        let snapshot = try RateLimitParser.parseResponse(data)
        #expect(snapshot.fiveHour?.remainingPercent == 80)
        #expect(snapshot.weekly?.remainingPercent == 70)
    }

    @Test("Timeout cleanup terminates a child that ignores SIGTERM")
    func boundedCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        try "#!/bin/sh\ntrap '' TERM\nwhile :; do sleep 0.1; done\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let start = ContinuousClock.now
        do {
            _ = try await CodexAppServerProvider(executableURL: executable, timeout: 0.3).fetch()
            Issue.record("Expected timeout")
        } catch {
            #expect(error as? QuotaReadError == .timedOut)
        }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test("Converts used percentages into remaining percentages")
    func parsesFiveHourAndWeeklyWindows() throws {
        let data = Data(
            """
            {
              "id": 2,
              "result": {
                "rateLimits": {
                  "planType": "plus",
                  "primary": {
                    "usedPercent": 6,
                    "windowDurationMins": 300,
                    "resetsAt": 1789241515
                  },
                  "secondary": {
                    "usedPercent": 2,
                    "windowDurationMins": 10080,
                    "resetsAt": 1789810223
                  }
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitParser.parseResponse(data)

        #expect(snapshot.fiveHour?.remainingPercent == 94)
        #expect(snapshot.fiveHour?.durationMinutes == 300)
        #expect(snapshot.weekly?.remainingPercent == 98)
        #expect(snapshot.weekly?.durationMinutes == 10080)
    }

    @Test("Finds windows by duration when the server changes their order")
    func selectsWindowsByDuration() throws {
        let data = Data(
            """
            {
              "id": 2,
              "result": {
                "rateLimitsByLimitId": {
                  "codex": {
                    "primary": { "usedPercent": 80, "windowDurationMins": 10080 },
                    "secondary": { "usedPercent": 25, "windowDurationMins": 300 }
                  }
                }
              }
            }
            """.utf8
        )

        let snapshot = try RateLimitParser.parseResponse(data)

        #expect(snapshot.fiveHour?.remainingPercent == 75)
        #expect(snapshot.weekly?.remainingPercent == 20)
    }

    @Test("Clamps values used by the renderer")
    func clampsRemainingPercent() {
        #expect(QuotaWindow(remainingPercent: -20).remainingPercent == 0)
        #expect(QuotaWindow(remainingPercent: 120).remainingPercent == 100)
        #expect(QuotaWindow(remainingPercent: 25).progress == 0.25)
    }

    @Test("Rejects responses without quota windows")
    func rejectsMissingWindows() {
        let data = Data(
            """
            { "id": 2, "result": { "rateLimits": {} } }
            """.utf8
        )

        #expect(throws: QuotaReadError.missingQuotaWindows) {
            try RateLimitParser.parseResponse(data)
        }
    }
}
