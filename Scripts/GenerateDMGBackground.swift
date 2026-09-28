//
//  GenerateDMGBackground.swift
//  Hangly
//
//  Draws the installer window's background at 1x and 2x. Run via
//  Scripts/build-dmg.sh, which combines the two into one Retina TIFF.
//

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@main
struct GenerateDMGBackground {
    /// The installer window's content size, in points. `build-dmg.sh` uses the same
    /// numbers to place the window and the two icons, so they cannot drift apart.
    static let size = CGSize(width: 620, height: 420)

    /// Where the two icons sit, in Finder's coordinates: origin top left, y down.
    static let appIcon = CGPoint(x: 170, y: 238)
    static let applicationsIcon = CGPoint(x: 450, y: 238)

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: background <charm svg> <out dir>\n".utf8))
            exit(2)
        }
        let charm = NSImage(contentsOfFile: arguments[0])
        let outputDirectory = URL(fileURLWithPath: arguments[1])
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for scale in [1, 2] {
            let image = try render(scale: CGFloat(scale), charm: charm)
            let name = scale == 1 ? "background.png" : "background@2x.png"
            try write(image, to: outputDirectory.appending(path: name))
        }
        print("Wrote background.png and background@2x.png to \(outputDirectory.path)")
    }

    // MARK: - Drawing

    static func render(scale: CGFloat, charm: NSImage?) throws -> CGImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        guard let context = CGContext(
            data: nil,
            width: Int(pixels.width),
            height: Int(pixels.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }

        // Draw in Finder's coordinates — origin top left, y down — so the numbers
        // here and the icon positions above mean the same thing.
        context.translateBy(x: 0, y: pixels.height)
        context.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        drawBackdrop(in: context)
        drawCharm(charm, in: context)
        drawWordmark(in: context)
        drawArrow(in: context)
        drawFooter(in: context)

        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        return image
    }

    /// Warm paper, a touch darker at the foot so the window has some weight.
    static func drawBackdrop(in context: CGContext) {
        let colors = [
            NSColor(srgbRed: 0.992, green: 0.988, blue: 0.980, alpha: 1).cgColor,
            NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 1).cgColor
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: [0, 1]
        ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: size.height),
            options: []
        )

        // A hairline along the foot, which reads as a shelf for the icons to sit on.
        context.setFillColor(NSColor(white: 0, alpha: 0.06).cgColor)
        context.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
    }

    /// The charm itself, hanging from the top edge of the window exactly as it hangs
    /// from the top of the screen. The artwork is the shipped asset, not a copy of it.
    static func drawCharm(_ charm: NSImage?, in context: CGContext) {
        guard let charm, charm.size.height > 0 else { return }
        let height: CGFloat = 148
        let width = charm.size.width / charm.size.height * height
        let rect = CGRect(x: 74, y: -6, width: width, height: height)

        // A soft shadow under it, so it sits in the window rather than on it.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor(white: 0, alpha: 0.18).cgColor)
        charm.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.restoreGState()
    }

    static func drawWordmark(in context: CGContext) {
        draw(
            "Hangly",
            at: CGPoint(x: 176, y: 58),
            font: .systemFont(ofSize: 34, weight: .semibold),
            color: NSColor(white: 0.12, alpha: 1)
        )
        draw(
            "A tiny piece of motion for your desktop.",
            at: CGPoint(x: 178, y: 100),
            font: .systemFont(ofSize: 13, weight: .regular),
            color: NSColor(white: 0.38, alpha: 1)
        )
    }

    /// Points from the app to the Applications folder, at the icons' own height.
    static func drawArrow(in context: CGContext) {
        let y = appIcon.y
        let start = CGPoint(x: appIcon.x + 78, y: y)
        let end = CGPoint(x: applicationsIcon.x - 78, y: y)

        context.setStrokeColor(NSColor(white: 0.62, alpha: 1).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [1, 7])
        context.move(to: start)
        context.addLine(to: CGPoint(x: end.x - 9, y: end.y))
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])

        context.setFillColor(NSColor(white: 0.62, alpha: 1).cgColor)
        context.move(to: end)
        context.addLine(to: CGPoint(x: end.x - 11, y: end.y - 6))
        context.addLine(to: CGPoint(x: end.x - 11, y: end.y + 6))
        context.closePath()
        context.fillPath()
    }

    static func drawFooter(in context: CGContext) {
        draw(
            "Drag Hangly into your Applications folder",
            at: CGPoint(x: 0, y: 356),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: NSColor(white: 0.42, alpha: 1),
            centredIn: size.width
        )
        draw(
            "Menu bar app · macOS 14 or later · Apple Silicon",
            at: CGPoint(x: 0, y: 379),
            font: .systemFont(ofSize: 10, weight: .regular),
            color: NSColor(white: 0.60, alpha: 1),
            centredIn: size.width
        )
    }

    // MARK: - Text

    static func draw(
        _ string: String,
        at origin: CGPoint,
        font: NSFont,
        color: NSColor,
        centredIn width: CGFloat? = nil
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let text = NSAttributedString(string: string, attributes: attributes)
        var point = origin
        if let width {
            point.x = (width - text.size().width) / 2
        }
        text.draw(at: point)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
