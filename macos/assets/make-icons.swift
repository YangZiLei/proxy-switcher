#!/usr/bin/env swift
import AppKit
import Foundation

// ============================================================
// proxy-switcher for macOS — Icon Generator
// Generates native macOS squircle icons with color gradients + letters.
// Outputs .icns and .png into macos/assets/icons/
// ============================================================

struct IconConfig {
    let key: String
    let letter: String
    let sub: String
    let topColor: NSColor
    let botColor: NSColor
    let accentColor: NSColor?
}

let configs: [IconConfig] = [
    // 代理切换 (Proxy Switcher) - Violet / Indigo
    IconConfig(
        key: "proxy",
        letter: "P",
        sub: "PROXY",
        topColor: NSColor(red: 0.45, green: 0.38, blue: 0.98, alpha: 1.0), // #7361FA
        botColor: NSColor(red: 0.24, green: 0.18, blue: 0.72, alpha: 1.0), // #3D2EB8
        accentColor: NSColor(red: 0.65, green: 0.55, blue: 1.0, alpha: 0.35)
    ),
    // Antigravity - Electric Blue / Cyan
    IconConfig(
        key: "antigravity",
        letter: "A",
        sub: "ANTIGRAVITY",
        topColor: NSColor(red: 0.05, green: 0.65, blue: 0.95, alpha: 1.0), // #0DA6F2
        botColor: NSColor(red: 0.10, green: 0.25, blue: 0.75, alpha: 1.0), // #1A40BF
        accentColor: NSColor(red: 0.30, green: 0.85, blue: 1.0, alpha: 0.35)
    ),
    // Gemini - Cosmic Gemini Gradient (Fuchsia to Indigo)
    IconConfig(
        key: "gemini",
        letter: "G",
        sub: "GEMINI",
        topColor: NSColor(red: 0.92, green: 0.28, blue: 0.60, alpha: 1.0), // #EA4799
        botColor: NSColor(red: 0.28, green: 0.32, blue: 0.90, alpha: 1.0), // #4752E6
        accentColor: NSColor(red: 0.40, green: 0.75, blue: 1.0, alpha: 0.35)
    ),
    // OpenCode - Emerald / Jade
    IconConfig(
        key: "opencode",
        letter: "O",
        sub: "OPENCODE",
        topColor: NSColor(red: 0.10, green: 0.78, blue: 0.50, alpha: 1.0), // #1AC780
        botColor: NSColor(red: 0.02, green: 0.45, blue: 0.32, alpha: 1.0), // #057352
        accentColor: NSColor(red: 0.35, green: 0.95, blue: 0.70, alpha: 0.35)
    ),
    // Grok (xAI) - Deep Carbon / Pitch Black
    IconConfig(
        key: "grok",
        letter: "X",
        sub: "GROK",
        topColor: NSColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1.0), // #33333D
        botColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0), // #14141A
        accentColor: NSColor(red: 0.90, green: 0.90, blue: 1.0, alpha: 0.35)
    )
]

func renderIcon(cfg: IconConfig) -> NSImage {
    let canvasSize = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: canvasSize)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    // 1. Drop shadow for the tile
    let tileRect = NSRect(x: 100, y: 120, width: 824, height: 824)
    let cornerRadius: CGFloat = 185
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -24),
        blur: 38,
        color: NSColor.black.withAlphaComponent(0.32).cgColor
    )
    NSColor.black.withAlphaComponent(0.01).setFill()
    tilePath.fill()
    ctx.restoreGState()

    // 2. Base tile with gradient
    ctx.saveGState()
    tilePath.addClip()

    let gradient = NSGradient(colors: [cfg.topColor, cfg.botColor])
    gradient?.draw(in: tileRect, angle: -55)

    // 2b. Subtle top glow / spotlight
    if let accent = cfg.accentColor {
        let glowCenter = CGPoint(x: 512, y: 880)
        let glowColors = [accent.cgColor, NSColor.clear.cgColor] as CFArray
        if let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(glowGrad, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: 450, options: [])
        }
    }

    // 2c. Subtle inner top border highlight
    let innerStrokeRect = tileRect.insetBy(dx: 1.5, dy: 1.5)
    let innerStrokePath = NSBezierPath(roundedRect: innerStrokeRect, xRadius: cornerRadius - 1.5, yRadius: cornerRadius - 1.5)
    innerStrokePath.lineWidth = 2.5
    NSColor.white.withAlphaComponent(0.22).setStroke()
    innerStrokePath.stroke()

    ctx.restoreGState()

    // 3. Central Letter
    let letterFont = NSFont.systemFont(ofSize: 440, weight: .heavy)
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.shadowBlurRadius = 14
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)

    let letterAttrs: [NSAttributedString.Key: Any] = [
        .font: letterFont,
        .foregroundColor: NSColor.white,
        .shadow: shadow
    ]
    let letterStr = cfg.letter as NSString
    let letterSize = letterStr.size(withAttributes: letterAttrs)

    let letterRect = NSRect(
        x: (1024 - letterSize.width) / 2,
        y: (1024 - letterSize.height) / 2 + 25,
        width: letterSize.width,
        height: letterSize.height
    )
    letterStr.draw(in: letterRect, withAttributes: letterAttrs)

    // 4. Subtitle / Label badge beneath the letter
    if !cfg.sub.isEmpty {
        let targetWidth: CGFloat = 550
        let approxFontSize: CGFloat = min(54, targetWidth / CGFloat(cfg.sub.count) * 0.95)
        let subFont = NSFont.systemFont(ofSize: approxFontSize, weight: .bold)
        let kern: CGFloat = cfg.sub.count > 6 ? 4.0 : 6.0
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            .kern: kern as NSNumber
        ]
        let subStr = cfg.sub as NSString
        let subSize = subStr.size(withAttributes: subAttrs)
        let subRect = NSRect(
            x: (1024 - subSize.width) / 2,
            y: 205,
            width: subSize.width,
            height: subSize.height
        )
        subStr.draw(in: subRect, withAttributes: subAttrs)
    }

    image.unlockFocus()
    return image
}

func resizedPNG(image: NSImage, pixelWidth: Int, pixelHeight: Int) -> Data? {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let bitmap = rep else { return nil }
    bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = ctx
    ctx?.imageInterpolation = .high

    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outDir = scriptDir.appendingPathComponent("icons")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for cfg in configs {
    print("Generating \(cfg.key) icon...")
    let masterImg = renderIcon(cfg: cfg)

    // 1. Save 1024x1024 master PNG
    if let pngData = resizedPNG(image: masterImg, pixelWidth: 1024, pixelHeight: 1024) {
        let pngURL = outDir.appendingPathComponent("\(cfg.key).png")
        try? pngData.write(to: pngURL)
    }

    // 2. Build .iconset folder
    let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(cfg.key).iconset")
    try? FileManager.default.removeItem(at: iconsetURL)
    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for entry in iconSizes {
        if let data = resizedPNG(image: masterImg, pixelWidth: entry.px, pixelHeight: entry.px) {
            let fileURL = iconsetURL.appendingPathComponent(entry.name)
            try? data.write(to: fileURL)
        }
    }

    // 3. Compile to .icns with iconutil
    let icnsURL = outDir.appendingPathComponent("\(cfg.key).icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
    try? process.run()
    process.waitUntilExit()

    try? FileManager.default.removeItem(at: iconsetURL)
    print("  ✓ \(icnsURL.lastPathComponent)")
}

print("All icons successfully generated in \(outDir.path)")
