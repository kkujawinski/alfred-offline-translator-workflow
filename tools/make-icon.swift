// Generates workflow/icon.png — the icon Alfred shows for the workflow.
//
//   swift tools/make-icon.swift [output.png]
//
// Uses AppKit and the system "translate" SF Symbol, so it needs no assets.

import AppKit

let side = 512
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "workflow/icon.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not allocate bitmap") }

let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let size = CGFloat(side)
let bounds = NSRect(x: 0, y: 0, width: size, height: size)

// macOS app-icon corner radius is about 22.37% of the side.
let plate = NSBezierPath(roundedRect: bounds, xRadius: size * 0.2237, yRadius: size * 0.2237)
plate.addClip()

NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.55, blue: 0.99, alpha: 1),
    NSColor(srgbRed: 0.31, green: 0.25, blue: 0.86, alpha: 1),
])!.draw(in: bounds, angle: -90)

let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.50, weight: .semibold)
guard let symbol = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translate")?
        .withSymbolConfiguration(configuration) else { fatalError("translate symbol unavailable") }

// Paint the symbol white by compositing a fill over its own alpha.
let glyph = NSImage(size: symbol.size, flipped: false) { rect in
    symbol.draw(in: rect)
    NSColor.white.setFill()
    rect.fill(using: .sourceAtop)
    return true
}

// Nudge up slightly: the glyph reads low when centred on a rounded plate.
let glyphRect = NSRect(
    x: (size - glyph.size.width) / 2,
    y: (size - glyph.size.height) / 2 + size * 0.012,
    width: glyph.size.width,
    height: glyph.size.height
)
glyph.draw(in: glyphRect)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(side)x\(side), \(png.count / 1024) KB)")
