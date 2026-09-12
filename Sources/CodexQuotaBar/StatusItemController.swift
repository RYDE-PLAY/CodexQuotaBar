import AppKit
import CodexQuotaBarCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store = QuotaStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    // AppKit measures titles even for custom views; full text belongs in the rows.
    private let fiveHourItem = NSMenuItem(title: "5h额度", action: nil, keyEquivalent: "")
    private let weeklyItem = NSMenuItem(title: "周额度", action: nil, keyEquivalent: "")
    private let fiveHourRow = QuotaMenuRowView(label: "5h额度：")
    private let weeklyRow = QuotaMenuRowView(label: "周额度：")
    private let devSpaceController = DevSpaceController()
    private let devSpaceItem = NSMenuItem(
        title: "DevSpace",
        action: nil,
        keyEquivalent: ""
    )
    private let devSpaceRow = DevSpaceMenuRowView()
    private lazy var quotaWarningIcon: NSImage? = {
        let image = NSImage(
            systemSymbolName: "exclamationmark.circle",
            accessibilityDescription: "额度数据提示"
        )
        image?.isTemplate = true
        return image
    }()
    private lazy var resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private lazy var resetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    private var refreshLoop: Task<Void, Never>?

    override init() {
        super.init()

        store.onChange = { [weak self] in
            self?.render()
        }
        devSpaceController.onChange = { [weak self] in
            self?.renderDevSpace()
        }
        devSpaceRow.onToggle = { [weak self] in
            self?.devSpaceController.toggle()
        }

        configureMenu()
        configureStatusItem()
    }

    func start() {
        render()
        renderDevSpace()
        store.refresh()
        devSpaceController.start()

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
        devSpaceController.refresh()
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

        devSpaceItem.isEnabled = true
        devSpaceItem.image = nil
        devSpaceItem.view = devSpaceRow
        menu.addItem(devSpaceItem)

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

    private func renderDevSpace() {
        devSpaceRow.isOn = devSpaceController.isEnabled
        devSpaceRow.isToggleEnabled = !devSpaceController.isBusy
        devSpaceRow.statusText = devSpaceController.statusText
        devSpaceRow.toolTip = devSpaceController.runtimeDescription
    }

    private func render() {
        let fiveHourProgress = store.snapshot?.fiveHour?.progress
        statusItem.button?.image = StatusIconRenderer.image(
            fiveHourProgress: fiveHourProgress,
            isStale: store.isStale
        )

        let fiveHourWindow = store.snapshot?.fiveHour
        let weeklyWindow = store.snapshot?.weekly
        let fiveHourLabel = quotaLabel(
            "5h额度",
            resetAt: fiveHourWindow?.resetsAt,
            formatter: resetTimeFormatter
        )
        let weeklyLabel = quotaLabel(
            "周额度",
            resetAt: weeklyWindow?.resetsAt,
            formatter: resetDateFormatter
        )
        let fiveHourValue = menuValue(window: fiveHourWindow)
        let weeklyValue = menuValue(window: weeklyWindow)
        fiveHourItem.setAccessibilityLabel("\(fiveHourLabel)\(fiveHourValue)")
        weeklyItem.setAccessibilityLabel("\(weeklyLabel)\(weeklyValue)")
        fiveHourRow.label = fiveHourLabel
        weeklyRow.label = weeklyLabel
        fiveHourRow.value = fiveHourValue
        weeklyRow.value = weeklyValue
        let labelWidth = max(
            58,
            fiveHourRow.preferredLabelWidth,
            weeklyRow.preferredLabelWidth
        )
        fiveHourRow.labelWidth = labelWidth
        weeklyRow.labelWidth = labelWidth
        fiveHourRow.statusToolTip = menuStatus(window: fiveHourWindow)
        weeklyRow.statusToolTip = menuStatus(window: weeklyWindow)
        fiveHourRow.statusIcon = fiveHourRow.statusToolTip == nil ? nil : quotaWarningIcon
        weeklyRow.statusIcon = weeklyRow.statusToolTip == nil ? nil : quotaWarningIcon

        let rowWidth = max(
            fiveHourRow.preferredWidth,
            weeklyRow.preferredWidth,
            devSpaceRow.preferredWidth
        )
        for row in [fiveHourRow, weeklyRow] {
            row.setFrameSize(
                NSSize(width: rowWidth, height: row.intrinsicContentSize.height)
            )
        }
        devSpaceRow.setFrameSize(
            NSSize(width: rowWidth, height: devSpaceRow.intrinsicContentSize.height)
        )

        let accessibilityText = accessibilityDescription()
        statusItem.button?.setAccessibilityValue(accessibilityText)
        statusItem.button?.toolTip = accessibilityText
    }

    private func menuValue(window: QuotaWindow?) -> String {
        guard let window else {
            if store.isLoading {
                return "读取中…"
            }
            return "—"
        }

        return "\(window.remainingPercent)% 剩余"
    }

    private func quotaLabel(
        _ title: String,
        resetAt: Date?,
        formatter: DateFormatter
    ) -> String {
        guard let resetAt else { return "\(title)：" }
        return "\(title)（~\(formatter.string(from: resetAt))）："
    }

    private func menuStatus(window: QuotaWindow?) -> String? {
        if window != nil {
            return store.staleDescription
        }

        guard !store.isLoading else { return nil }
        return store.errorMessage ?? "没有读取到这项额度"
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
