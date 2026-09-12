import AppKit

@MainActor
final class DevSpaceMenuRowView: NSView {
    private static let minimumSize = NSSize(width: 220, height: 44)

    var preferredWidth: CGFloat {
        let textWidth = max(
            titleField.intrinsicContentSize.width,
            statusField.intrinsicContentSize.width
        )
        return max(
            Self.minimumSize.width,
            16
                + textWidth
                + 20
                + toggle.intrinsicContentSize.width
                + 16
        )
    }

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }

    var isToggleEnabled: Bool {
        get { toggle.isEnabled }
        set { toggle.isEnabled = newValue }
    }

    var statusText: String {
        get { statusField.stringValue }
        set { statusField.stringValue = newValue }
    }

    var onToggle: (() -> Void)?

    private let titleField = NSTextField(labelWithString: "DevSpace")
    private let statusField = NSTextField(labelWithString: "读取状态…")
    private let toggle = AccentSwitchControl()

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.minimumSize))

        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        statusField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingTail
        statusField.usesSingleLineMode = true

        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.setAccessibilityLabel("DevSpace")

        for view in [titleField, statusField, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleField.trailingAnchor.constraint(
                lessThanOrEqualTo: toggle.leadingAnchor,
                constant: -12
            ),

            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            statusField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            statusField.trailingAnchor.constraint(
                lessThanOrEqualTo: toggle.leadingAnchor,
                constant: -12
            ),
            statusField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -5)
        ])
    }

    convenience init() {
        self.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Self.minimumSize
    }

    @objc private func toggleChanged(_ sender: AccentSwitchControl) {
        onToggle?()
    }
}

@MainActor
final class AccentSwitchControl: NSControl {
    private static let size = NSSize(width: 38, height: 22)
    private static let inset: CGFloat = 2

    var isOn = false {
        didSet {
            guard oldValue != isOn else { return }
            needsDisplay = true
            setAccessibilityValue(isOn ? "1" : "0")
        }
    }

    override var intrinsicContentSize: NSSize {
        Self.size
    }

    override var isEnabled: Bool {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: CGRect(origin: .zero, size: Self.size))
        focusRingType = .none
        setAccessibilityValue("0")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )

        let trackColor: NSColor
        if isOn {
            trackColor = NSColor.controlAccentColor.withAlphaComponent(isEnabled ? 1.0 : 0.42)
        } else {
            trackColor = NSColor.controlColor.withAlphaComponent(isEnabled ? 0.62 : 0.32)
        }
        trackColor.setFill()
        trackPath.fill()

        let knobDiameter = bounds.height - (Self.inset * 2)
        let knobX = isOn
            ? bounds.width - knobDiameter - Self.inset
            : Self.inset
        let knobRect = NSRect(
            x: knobX,
            y: Self.inset,
            width: knobDiameter,
            height: knobDiameter
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
        shadow.set()

        NSColor.white.withAlphaComponent(isEnabled ? 1.0 : 0.72).setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        isOn.toggle()
        sendAction(action, to: target)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }

        isOn.toggle()
        sendAction(action, to: target)
        return true
    }
}
