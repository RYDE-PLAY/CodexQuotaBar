import AppKit

@MainActor
final class QuotaMenuRowView: NSView {
    private static let rowSize = NSSize(width: 180, height: 22)
    var preferredWidth: CGFloat {
        max(Self.rowSize.width, 32 + 58 + 8 + valueField.intrinsicContentSize.width)
    }
    private let labelField: NSTextField
    private let valueField: NSTextField

    var value: String {
        get { valueField.stringValue }
        set { valueField.stringValue = newValue }
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

        labelField.translatesAutoresizingMaskIntoConstraints = false
        valueField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)
        addSubview(valueField)

        labelField.setContentHuggingPriority(.required, for: .horizontal)
        labelField.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.widthAnchor.constraint(equalToConstant: 58),

            valueField.leadingAnchor.constraint(equalTo: labelField.trailingAnchor, constant: 8),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        Self.rowSize
    }
}
