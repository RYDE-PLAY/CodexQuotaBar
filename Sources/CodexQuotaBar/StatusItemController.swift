import AppKit
import CodexQuotaBarCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store = QuotaStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let fiveHourItem = NSMenuItem(title: "5h额度：读取中…", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "周额度：读取中…", action: nil, keyEquivalent: "")
    private let fiveHourRow = QuotaMenuRowView(label: "5h额度：")
    private let weeklyRow = QuotaMenuRowView(label: "周额度：")
    private var refreshLoop: Task<Void, Never>?

    override init() {
        super.init()

        store.onChange = { [weak self] in
            self?.render()
        }

        configureMenu()
        configureStatusItem()
    }

    func start() {
        render()
        store.refresh()

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.store.refresh()
            }
        }
    }

    deinit {
        refreshLoop?.cancel()
    }

    func menuWillOpen(_ menu: NSMenu) {
        store.refreshIfNeeded()
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.imageScaling = .scaleProportionallyDown
        statusItem.button?.setAccessibilityLabel("Codex 额度")
        statusItem.button?.toolTip = "Codex 额度"
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        fiveHourItem.isEnabled = false
        weeklyItem.isEnabled = false
        fiveHourItem.image = nil
        weeklyItem.image = nil
        fiveHourItem.view = fiveHourRow
        weeklyItem.view = weeklyRow

        menu.addItem(fiveHourItem)
        menu.addItem(weeklyItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(terminateApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.image = nil
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func terminateApplication(_ sender: Any?) {
        NSApplication.shared.terminate(sender)
    }

    private func render() {
        let fiveHourProgress = store.snapshot?.fiveHour?.progress
        statusItem.button?.image = StatusIconRenderer.image(
            fiveHourProgress: fiveHourProgress,
            isStale: store.isStale
        )

        let fiveHourValue = menuValue(window: store.snapshot?.fiveHour)
        let weeklyValue = menuValue(window: store.snapshot?.weekly)
        fiveHourItem.title = "5h额度：\(fiveHourValue)"
        weeklyItem.title = "周额度：\(weeklyValue)"
        fiveHourRow.value = fiveHourValue
        weeklyRow.value = weeklyValue
        let rowWidth = max(fiveHourRow.preferredWidth, weeklyRow.preferredWidth)
        for row in [fiveHourRow, weeklyRow] {
            row.setFrameSize(NSSize(width: rowWidth, height: row.intrinsicContentSize.height))
        }

        let accessibilityText = accessibilityDescription()
        statusItem.button?.setAccessibilityValue(accessibilityText)
        statusItem.button?.toolTip = accessibilityText
    }

    private func menuValue(window: QuotaWindow?) -> String {
        guard let window else {
            if store.isLoading {
                return "读取中…"
            }
            return "—（无法读取）"
        }

        let suffix = store.isStale ? "（数据已过期）" : ""
        return "\(window.remainingPercent)% 剩余\(suffix)"
    }

    private func accessibilityDescription() -> String {
        guard let snapshot = store.snapshot else {
            return store.isLoading ? "Codex 额度，正在读取" : "Codex 额度，无法读取"
        }

        let fiveHour = snapshot.fiveHour.map { "5 小时剩余 \($0.remainingPercent)%" } ?? "5 小时不可用"
        let weekly = snapshot.weekly.map { "周额度剩余 \($0.remainingPercent)%" } ?? "周额度不可用"
        let stale = store.isStale ? "，数据已过期" : ""
        return "Codex 额度，\(fiveHour)，\(weekly)\(stale)"
    }
}
