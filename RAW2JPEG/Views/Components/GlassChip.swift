import SwiftUI

// MARK: - Glass Chip Modifier

extension View {
    func glassChip(isActive: Bool) -> some View {
        self.modifier(GlassChipModifier(isActive: isActive))
    }
}

struct GlassChipModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(isActive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            content
                .background(
                    isActive ? AnyShapeStyle(Color.blue.opacity(0.3)) : AnyShapeStyle(Color.white.opacity(0.08)),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

// MARK: - Primary Action Fill

extension ShapeStyle where Self == LinearGradient {
    /// Gradient used for prominent primary-action buttons.
    static var primaryAction: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color(red: 0.0, green: 0.45, blue: 0.95)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

extension View {
    /// Fills a primary-action button with the app's accent gradient and a soft
    /// glow, keeping the label content white. Use on the label of key buttons.
    func prominentFill(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient.primaryAction)
                    .shadow(color: .blue.opacity(0.35), radius: 10, y: 4)
            )
            .foregroundStyle(.white)
    }
}
