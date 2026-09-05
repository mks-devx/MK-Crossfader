import SwiftUI

struct LearnActionButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = isEnabled ? (primary ? "D8D9D6" : "4C5055") : "303236"
        let text = isEnabled ? (primary ? "171817" : "F3F3F1") : "A9ABB0"
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .foregroundStyle(Color(rgbHex: text))
            .background(Color(rgbHex: fill), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                Color(rgbHex: isEnabled ? "85898F" : "53565B"), lineWidth: 1
            ))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
