import AppKit
import CoreGraphics
import Foundation

private let canvasSize: CGFloat = 1024

private func color(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat
) -> CGColor {
    CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [red / 255, green / 255, blue / 255, 1]
    )!
}

private func fillPolygon(
    _ coordinates: [(CGFloat, CGFloat)],
    color: CGColor,
    in context: CGContext
) {
    guard let first = coordinates.first else {
        return
    }

    let path = CGMutablePath()
    path.move(to: CGPoint(x: first.0, y: first.1))
    for point in coordinates.dropFirst() {
        path.addLine(to: CGPoint(x: point.0, y: point.1))
    }
    path.closeSubpath()

    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

private func renderIcon(size: Int, to outputURL: URL) throws {
    guard size > 0,
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let scale = CGFloat(size) / canvasSize
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: scale, y: -scale)

    let tile = CGPath(
        roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
        cornerWidth: 205,
        cornerHeight: 205,
        transform: nil
    )
    context.addPath(tile)
    context.setFillColor(color(red: 16, green: 16, blue: 18))
    context.fillPath()

    let border = CGPath(
        roundedRect: CGRect(x: 49, y: 49, width: 926, height: 926),
        cornerWidth: 204,
        cornerHeight: 204,
        transform: nil
    )
    context.addPath(border)
    context.setStrokeColor(color(red: 48, green: 48, blue: 52))
    context.setLineWidth(2)
    context.strokePath()

    let light = color(red: 243, green: 243, blue: 241)
    let grey = color(red: 136, green: 136, blue: 140)
    func markPoints(
        _ coordinates: [(CGFloat, CGFloat)]
    ) -> [(CGFloat, CGFloat)] {
        coordinates.map { point in
            (102 + point.0 * 1.28, 102 + point.1 * 1.28)
        }
    }
    fillPolygon(
        markPoints([
            (48, 178), (282, 178), (346, 252), (290, 252),
            (258, 218), (48, 218),
        ]),
        color: light,
        in: context
    )
    fillPolygon(
        markPoints([
            (48, 282), (230, 282), (278, 330), (278, 358),
            (254, 358), (214, 322), (48, 322),
        ]),
        color: light,
        in: context
    )
    fillPolygon(
        markPoints([(282, 280), (354, 280), (354, 358), (282, 358)]),
        color: light,
        in: context
    )
    fillPolygon(
        markPoints([
            (378, 280), (396, 298), (592, 298), (592, 324),
            (378, 324),
        ]),
        color: grey,
        in: context
    )
    fillPolygon(
        markPoints([
            (378, 364), (592, 364), (592, 408), (400, 408),
            (378, 386),
        ]),
        color: grey,
        in: context
    )
    fillPolygon(
        markPoints([
            (282, 386), (316, 386), (392, 462), (592, 462),
            (592, 506), (376, 506),
        ]),
        color: grey,
        in: context
    )

    guard let image = context.makeImage() else {
        throw CocoaError(.fileWriteUnknown)
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: outputURL, options: .atomic)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty, arguments.count.isMultiple(of: 2) else {
    fputs("Usage: render-icon.swift <size> <output.png> [...]\n", stderr)
    exit(64)
}

for index in stride(from: 0, to: arguments.count, by: 2) {
    guard let size = Int(arguments[index]), size > 0 else {
        fputs("Invalid icon size: \(arguments[index])\n", stderr)
        exit(64)
    }
    try renderIcon(
        size: size,
        to: URL(fileURLWithPath: arguments[index + 1])
    )
}
