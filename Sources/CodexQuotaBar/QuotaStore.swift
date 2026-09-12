import Foundation
import CodexQuotaBarCore

@MainActor
final class QuotaStore {
    private(set) var snapshot: QuotaSnapshot?
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    var onChange: (() -> Void)?

    private var provider: CodexAppServerProvider?
    private var refreshTask: Task<Void, Never>?
    private let staleAfter: TimeInterval = 10 * 60

    init() {
        provider = makeProvider()
        if provider == nil {
            errorMessage = QuotaReadError.codexNotFound.localizedDescription
        }
    }

    var isStale: Bool {
        guard let snapshot else { return true }
        return errorMessage != nil || Date().timeIntervalSince(snapshot.updatedAt) > staleAfter
    }

    var staleDescription: String? {
        guard isStale else { return nil }

        guard snapshot != nil else {
            return errorMessage ?? (isLoading ? "正在读取 Codex 额度" : "无法读取 Codex 额度")
        }

        if let errorMessage {
            return "最近一次刷新失败：\(errorMessage)，当前显示上次成功读取的数据"
        }
        return "超过 10 分钟未成功刷新，当前显示上次成功读取的数据"
    }

    func refreshIfNeeded() {
        guard refreshTask == nil else { return }
        if let snapshot, Date().timeIntervalSince(snapshot.updatedAt) < 60, errorMessage == nil {
            return
        }
        refresh()
    }

    func refresh() {
        guard refreshTask == nil else { return }

        if provider == nil {
            provider = makeProvider()
        }
        guard let provider else {
            errorMessage = QuotaReadError.codexNotFound.localizedDescription
            notifyChange()
            return
        }

        isLoading = true
        notifyChange()

        refreshTask = Task { [weak self] in
            do {
                let snapshot = try await provider.fetch()
                guard !Task.isCancelled else { return }
                self?.snapshot = snapshot
                self?.errorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self?.errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "无法读取 Codex 额度"
            }

            guard !Task.isCancelled else { return }
            self?.isLoading = false
            self?.refreshTask = nil
            self?.notifyChange()
        }
    }

    private func makeProvider() -> CodexAppServerProvider? {
        guard let executableURL = CodexExecutableLocator.locate() else {
            return nil
        }
        return CodexAppServerProvider(executableURL: executableURL)
    }

    private func notifyChange() {
        onChange?()
    }
}
