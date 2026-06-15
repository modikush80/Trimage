import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024

/// Recolor a template SF Symbol image to a solid color.
func recolored(_ image: NSImage, _ color: NSColor) -> NSImage {
    let copy = image.copy() as! NSImage
    copy.lockFocus()
    color.set()
    NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
    copy.unlockFocus()
    copy.isTemplate = false
    return copy
}

/// Write a CGImage to PNG, optionally stripping the alpha channel (required for
/// the primary iOS app icon, which must be fully opaque).
func writePNG(_ image: CGImage, opaque: Bool, to path: String) {
    var out = image
    if opaque {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: Int(size), height: Int(size),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        out = ctx.makeImage()!
    }
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path)")
}

/// Render one icon variant into an RGBA context, then write it.
func makeIcon(gradient: [(NSColor, CGFloat)]?, glyphColor: NSColor, opaque: Bool = false, to path: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("rep") }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsctx
    let cg = nsctx.cgContext

    // Background gradient (diagonal), or leave transparent.
    if let stops = gradient {
        let colors = stops.map { $0.0.cgColor } as CFArray
        let locs = stops.map { $0.1 }
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
            cg.drawLinearGradient(grad,
                                  start: CGPoint(x: 0, y: size),
                                  end: CGPoint(x: size, y: 0),
                                  options: [])
        }
        // Soft radial highlight for depth.
        let glowColors = [NSColor(white: 1, alpha: 0.16).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray
        if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
            cg.drawRadialGradient(glow,
                                  startCenter: CGPoint(x: size * 0.32, y: size * 0.72), startRadius: 0,
                                  endCenter: CGPoint(x: size * 0.32, y: size * 0.72), endRadius: size * 0.6,
                                  options: [])
        }
    }

    // Aperture glyph, centered.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.58, weight: .light)
    if let base = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: nil),
       let sym = base.withSymbolConfiguration(config) {
        let tinted = recolored(sym, glyphColor)
        let g = tinted.size
        let origin = NSPoint(x: (size - g.width) / 2, y: (size - g.height) / 2)
        tinted.draw(in: NSRect(origin: origin, size: g),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        FileHandle.standardError.write("WARNING: SF Symbol unavailable\n".data(using: .utf8)!)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = rep.cgImage else { fatalError("cgImage") }
    writePNG(cgImage, opaque: opaque, to: path)
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// Light/any: opaque indigo→near-black gradient, white glyph (NO alpha channel).
makeIcon(
    gradient: [
        (NSColor(red: 0.20, green: 0.09, blue: 0.42, alpha: 1), 0.0),
        (NSColor(red: 0.07, green: 0.03, blue: 0.16, alpha: 1), 0.55),
        (NSColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1), 1.0)
    ],
    glyphColor: .white,
    opaque: true,
    to: "\(dir)/AppIcon-Light.png"
)

// Dark: transparent background (system supplies dark bg), white glyph.
makeIcon(gradient: nil, glyphColor: .white, to: "\(dir)/AppIcon-Dark.png")

// Tinted: transparent background, white grayscale glyph (system applies tint).
makeIcon(gradient: nil, glyphColor: .white, to: "\(dir)/AppIcon-Tinted.png")
