import Foundation

public struct QuotaWindow: Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(
        remainingPercent: Int,
        resetsAt: Date? = nil,
        durationMinutes: Int? = nil
    ) {
        self.remainingPercent = min(max(remainingPercent, 0), 100)
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    public var progress: Double {
        Double(remainingPercent) / 100.0
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let fiveHour: QuotaWindow?
    public let weekly: QuotaWindow?
    public let updatedAt: Date

    public init(
        fiveHour: QuotaWindow?,
        weekly: QuotaWindow?,
        updatedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.updatedAt = updatedAt
    }
}

public enum QuotaReadError: LocalizedError, Equatable, Sendable {
    case codexNotFound
    case launchFailed(String)
    case timedOut
    case processFailed(Int32)
    case protocolError(String)
    case missingQuotaWindows

    public var errorDescription: String? {
        switch self {
        case .codexNotFound:
            "未找到 Codex CLI"
        case .launchFailed:
            "无法启动 Codex CLI"
        case .timedOut:
            "读取额度超时"
        case .processFailed:
            "Codex CLI 读取失败"
        case .protocolError:
            "Codex 返回的数据无法识别"
        case .missingQuotaWindows:
            "Codex 没有返回 5 小时或周额度"
        }
    }
}
