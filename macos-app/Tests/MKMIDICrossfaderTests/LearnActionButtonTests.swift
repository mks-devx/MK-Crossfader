import AppKit
import SwiftUI
import Testing
@testable import MKMIDICrossfader

@Test("Learn buttons render at stable sizes in light and dark appearances")
@MainActor
func learnButtonAppearance() throws {
    for scheme in [ColorScheme.light, .dark] {
        let content = VStack(alignment: .leading, spacing: 16) {
            ForEach([true, false], id: \.self) { enabled in
                HStack(spacing: 16) {
                    Button {} label: { Label("MIDI Learn", systemImage: "dot.radiowaves.left.and.right") }
                        .buttonStyle(LearnActionButtonStyle(primary: true))
                    Button {} label: { Label("Cancel", systemImage: "xmark.circle") }
                        .buttonStyle(LearnActionButtonStyle(primary: true))
                    Button {} label: { Label("Send Learn", systemImage: "paperplane.fill") }
                        .buttonStyle(LearnActionButtonStyle())
                }
                .disabled(!enabled)
            }
        }
        .padding(24)
        .frame(width: 560, height: 160)
        .background(scheme == .dark ? Color.black : Color.white)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == 1120 && image.height == 320)
        if let directory = ProcessInfo.processInfo.environment["MK_CROSSFADER_TEST_ARTIFACTS"] {
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            let file = scheme == .dark ? "learn-buttons-dark.png" : "learn-buttons-light.png"
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(file))
        }
    }
}
