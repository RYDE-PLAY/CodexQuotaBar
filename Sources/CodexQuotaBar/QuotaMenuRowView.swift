import AppKit

@MainActor
final class QuotaMenuRowView: NSView {
    private static let rowSize = NSSize(width: 180, height: 22)
    var preferredWidth: CGFloat {
        let labelWidth = labelWidthConstraint?.constant ?? 58
        let valueWidth = valueField.intrinsicContentSize.width
        let statusWidth: CGFloat = statusImageView.image == nil ? 0 : 18
        let contentWidth = 32 + labelWidth + 8 + valueWidth + statusWidth
        return max(Self.rowSize.width, contentWidth)
    }
    private let labelField: NSTextField
    private let valueField: NSTextField
    private let statusImageView = NSImageView()
    private var labelWidthConstraint: NSLayoutConstraint!
    private var statusImageWidthConstraint: NSLayoutConstraint!

    var preferredLabelWidth: CGFloat {
        labelField.intrinsicContentSize.width
    }

    var labelWidth: CGFloat {
        get { labelWidthConstraint.constant }
        set { labelWidthConstraint.constant = newValue }
    }

    var value: String {
        get { valueField.stringValue }
        set { valueField.stringValue = newValue }
    }

    var label: String {
        get { labelField.stringValue }
        set { labelField.stringValue = newValue }
    }

    var statusIcon: NSImage? {
        get { statusImageView.image }
        set {
            statusImageView.image = newValue
            statusImageView.isHidden = newValue == nil
            statusImageWidthConstraint.constant = newValue == nil ? 0 : 14
        }
    }

    var statusToolTip: String? {
        didSet {
            toolTip = statusToolTip
            valueField.toolTip = statusToolTip
            statusImageView.toolTip = statusToolTip
        }
    }

    init(label: String) {
        labelField = NSTextField(labelWithString: label)
        valueField = NSTextField(labelWithString: "")
        super.init(frame: CGRect(origin: .zero, size: Self.rowSize))

        labelField.font = NSFont.menuFont(ofSize: 0)
        labelField.textColor = .secondaryLabelColor
        labelField.lineBreakMode = .byTruncatingTail

        valueField.font = NSFont.menuFont(ofSize: 0)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right
        valueField.lineBreakMode = .byTruncatingTail
        valueField.usesSingleLineMode = true

        statusImageView.imageScaling = .scaleProportionallyDown
        statusImageView.imageAlignment = .alignCenter
        statusImageView.contentTintColor = .secondaryLabelColor
        statusImageView.isHidden = true

        labelField.translatesAutoresizingMaskIntoConstraints = false
        valueField.translatesAutoresizingMaskIntoConstraints = false
        statusImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        addSubview(valueField)
        addSubview(statusImageView)

        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusImageView.setContentHuggingPriority(.required, for: .horizontal)
        statusImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        labelWidthConstraint = labelField.widthAnchor.constraint(equalToConstant: 58)
        statusImageWidthConstraint = statusImageView.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelWidthConstraint,

            valueField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: statusImageView.leadingAnchor, constant: -4),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),

            statusImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusImageView.heightAnchor.constraint(equalToConstant: 14),
            statusImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusImageWidthConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Self.rowSize
    }
}
