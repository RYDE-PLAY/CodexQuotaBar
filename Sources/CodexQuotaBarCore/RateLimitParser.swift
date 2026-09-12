import Foundation

public enum RateLimitParser {
    public static func parseResponse(
        _ data: Data,
        updatedAt: Date = Date()
    ) throws -> QuotaSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw QuotaReadError.protocolError("JSON")
        }

        guard let root = object as? [String: Any] else {
            throw QuotaReadError.protocolError("root")
        }

        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "error"
            throw QuotaReadError.protocolError(message)
        }

        guard let result = root["result"] as? [String: Any] else {
            throw QuotaReadError.protocolError("result")
        }

        let rateLimits = rateLimitSnapshot(from: result)
        guard let rateLimits else {
            throw QuotaReadError.missingQuotaWindows
        }

        let primary = parseWindow(rateLimits["primary"])
        let secondary = parseWindow(rateLimits["secondary"])
        let windows = [primary, secondary].compactMap { $0 }

        let fiveHour = windows.first(where: { $0.durationMinutes == 300 })
            ?? (primary?.durationMinutes == nil ? primary : nil)
        let weekly = windows.first(where: { $0.durationMinutes == 10_080 })
            ?? (secondary?.durationMinutes == nil ? secondary : nil)
        guard fiveHour != nil || weekly != nil else {
            throw QuotaReadError.missingQuotaWindows
        }

        return QuotaSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            updatedAt: updatedAt
        )
    }

    private static func rateLimitSnapshot(from result: [String: Any]) -> [String: Any]? {
        if let buckets = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = buckets["codex"] as? [String: Any] {
            return codex
        }

        return result["rateLimits"] as? [String: Any]
    }

    private static func parseWindow(_ value: Any?) -> QuotaWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = integer(dictionary["usedPercent"]) else {
            return nil
        }

        let resetDate = integer64(dictionary["resetsAt"])
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let durationMinutes = integer(dictionary["windowDurationMins"])

        return QuotaWindow(
            remainingPercent: 100 - usedPercent,
            resetsAt: resetDate,
            durationMinutes: durationMinutes
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func integer64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        return nil
    }
}
