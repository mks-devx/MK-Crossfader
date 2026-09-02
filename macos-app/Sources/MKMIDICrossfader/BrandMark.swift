import AppKit
import SwiftUI

@MainActor
enum BrandAssets {
    static let menuBarIcon: NSImage = {
        let image = NSImage(
            size: NSSize(width: 20, height: 13),
            flipped: true
        ) { bounds in
            let sourceSize = CGSize(width: 544, height: 328)
            let scale = min(
                bounds.width / sourceSize.width,
                bounds.height / sourceSize.height
            )
            let offset = CGPoint(
                x: (bounds.width - sourceSize.width * scale) / 2,
                y: (bounds.height - sourceSize.height * scale) / 2
            )

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: offset.x + x * scale,
                    y: offset.y + y * scale
                )
            }

            func fill(_ points: [CGPoint]) {
                guard let first = points.first else {
                    return
                }
                let path = NSBezierPath()
                path.move(to: first)
                for point in points.dropFirst() {
                    path.line(to: point)
                }
                path.close()
                path.fill()
            }

            NSColor.black.setFill()
            fill([
                point(0, 0), point(234, 0), point(298, 74),
                point(242, 74), point(210, 40), point(0, 40),
            ])
            fill([
                point(0, 104), point(182, 104), point(230, 152),
                point(230, 180), point(206, 180), point(166, 144),
                point(0, 144),
            ])
            NSBezierPath(
                rect: CGRect(
                    x: offset.x + 234 * scale,
                    y: offset.y + 102 * scale,
                    width: 72 * scale,
                    height: 78 * scale
                )
            ).fill()
            fill([
                point(330, 102), point(348, 120), point(544, 120),
                point(544, 146), point(330, 146),
            ])
            fill([
                point(330, 186), point(544, 186), point(544, 230),
                point(352, 230), point(330, 208),
            ])
            fill([
                point(234, 208), point(268, 208), point(344, 284),
                point(544, 284), point(544, 328), point(328, 328),
            ])
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MK Crossfader"
        return image
    }()
}

struct MenuBarRouteMark: View {
    let isActive: Bool

    var body: some View {
        Image(nsImage: BrandAssets.menuBarIcon)
            .renderingMode(.template)
            .opacity(isActive ? 1 : 0.68)
            .accessibilityLabel("MK Crossfader")
    }
}

struct RouteMark: View {
    var leftColor: Color = .primary
    var rightColor: Color = .secondary

    var body: some View {
        Canvas { context, size in
            let sourceSize = CGSize(width: 544, height: 328)
            let scale = min(
                size.width / sourceSize.width,
                size.height / sourceSize.height
            )
            let offset = CGPoint(
                x: (size.width - sourceSize.width * scale) / 2,
                y: (size.height - sourceSize.height * scale) / 2
            )

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: offset.x + x * scale,
                    y: offset.y + y * scale
                )
            }

            func polygon(_ points: [CGPoint]) -> Path {
                var path = Path()
                guard let first = points.first else {
                    return path
                }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
                return path
            }

            let leftTop = polygon([
                point(0, 0), point(234, 0), point(298, 74),
                point(242, 74), point(210, 40), point(0, 40),
            ])
            let leftBottom = polygon([
                point(0, 104), point(182, 104), point(230, 152),
                point(230, 180), point(206, 180), point(166, 144),
                point(0, 144),
            ])
            let rightTop = polygon([
                point(330, 102), point(348, 120), point(544, 120),
                point(544, 146), point(330, 146),
            ])
            let rightMiddle = polygon([
                point(330, 186), point(544, 186), point(544, 230),
                point(352, 230), point(330, 208),
            ])
            let rightBottom = polygon([
                point(234, 208), point(268, 208), point(344, 284),
                point(544, 284), point(544, 328), point(328, 328),
            ])

            context.fill(leftTop, with: .color(leftColor))
            context.fill(leftBottom, with: .color(leftColor))
            context.fill(
                Path(
                    CGRect(
                        x: offset.x + 234 * scale,
                        y: offset.y + 102 * scale,
                        width: 72 * scale,
                        height: 78 * scale
                    )
                ),
                with: .color(leftColor)
            )
            context.fill(rightTop, with: .color(rightColor))
            context.fill(rightMiddle, with: .color(rightColor))
            context.fill(rightBottom, with: .color(rightColor))
        }
    }
}
