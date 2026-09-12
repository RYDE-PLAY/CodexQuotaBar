import AppKit

enum StatusIconRenderer {
    private static let imageSize = NSSize(width: 18, height: 18)
    private static let logoRect = CGRect(x: 0, y: 0, width: 18, height: 18)
    private static let logoCenter = CGPoint(x: 9, y: 9)
    private static let chatGPTTemplate = loadChatGPTTemplate()

    static func image(
        fiveHourProgress: Double?,
        isStale: Bool
    ) -> NSImage {
        let image = NSImage(size: imageSize)
        image.isTemplate = true
        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return image
        }

        context.setShouldAntialias(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let fillAlpha: CGFloat = isStale ? 0.62 : 1.0
        let logoAlpha: CGFloat = isStale ? 0.18 : 0.28

        drawChatGPTMark(
            in: context,
            progress: fiveHourProgress,
            baseAlpha: logoAlpha,
            fillAlpha: fillAlpha
        )

        return image
    }

    private static func drawChatGPTMark(
        in context: CGContext,
        progress: Double?,
        baseAlpha: CGFloat,
        fillAlpha: CGFloat
    ) {
        if let progress, progress >= 1 {
            drawLogo(in: context, alpha: fillAlpha)
            return
        }
        // Start with a dimmed logo. The opaque sector below is the remaining quota;
        // the unfilled sector therefore stays genuinely translucent.
        drawLogo(in: context, alpha: baseAlpha)

        guard let progress else { return }
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > 0 else { return }

        // The dimmed sector starts at 12 o'clock and grows clockwise as quota is
        // consumed. Fill the complementary sector with the remaining quota.
        let consumedProgress = 1 - clampedProgress

        context.saveGState()
        defer { context.restoreGState() }

        context.beginPath()
        context.move(to: logoCenter)
        context.addArc(
            center: logoCenter,
            radius: 24,
            startAngle: .pi / 2 - (2 * .pi * consumedProgress),
            endAngle: .pi / 2,
            clockwise: true
        )
        context.closePath()
        context.clip()

        drawLogo(in: context, alpha: fillAlpha)
    }

    private static func drawLogo(in context: CGContext, alpha: CGFloat) {
        if let chatGPTTemplate {
            chatGPTTemplate.draw(
                in: logoRect,
                from: .zero,
                operation: .sourceOver,
                fraction: alpha,
                respectFlipped: true,
                hints: nil
            )
            return
        }

        drawFallbackRosette(in: context, alpha: alpha)
    }

    private static func drawFallbackRosette(in context: CGContext, alpha: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: logoCenter.x, y: logoCenter.y)
        context.setLineWidth(1.25)
        context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.setLineCap(.round)

        for index in 0..<6 {
            context.saveGState()
            context.rotate(by: CGFloat(index) * (.pi / 3))
            context.strokeEllipse(in: CGRect(x: 0.6, y: -1.75, width: 5.1, height: 3.5))
            context.restoreGState()
        }

        context.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.fillEllipse(in: CGRect(x: -0.85, y: -0.85, width: 1.7, height: 1.7))
    }

    private static func loadChatGPTTemplate() -> NSImage? {
        let paths = [
            Bundle.main.path(forResource: "chatgptTemplate@2x", ofType: "png"),
            Bundle.main.path(forResource: "chatgptTemplate", ofType: "png"),
            "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate@2x.png",
            "/Applications/ChatGPT.app/Contents/Resources/chatgptTemplate.png"
        ].compactMap { $0 }

        for path in paths {
            guard let image = NSImage(contentsOfFile: path) else { continue }
            image.isTemplate = true
            return image
        }

        return nil
    }

}
