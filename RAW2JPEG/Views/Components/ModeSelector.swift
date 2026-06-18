import SwiftUI

// MARK: - Mode Selector

/// A custom sliding segmented control with SF Symbols, styled to match the
/// app's dark glass aesthetic. Replaces the plain segmented `Picker` for a
/// more polished, HIG-aligned feel. The selection indicator slides between
/// segments using `matchedGeometryEffect`.
struct ModeSelector: View {
    @Binding var mode: AppState.LibraryMode
    var isEnabled: Bool = true

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppState.LibraryMode.allCases) { item in
                segment(for: item)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .allowsHitTesting(isEnabled)
    }

    private func segment(for item: AppState.LibraryMode) -> some View {
        let isSelected = (item == mode)
        return Button {
            guard isEnabled else { return }
            withAnimation(.snappy(duration: 0.3, extraBounce: 0.1)) {
                mode = item
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.icon)
                    .font(.subheadline.weight(.semibold))
                Text(item.shortTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue)
                        .shadow(color: .blue.opacity(0.45), radius: 8, y: 3)
                        .matchedGeometryEffect(id: "selectedSegment", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.shortTitle)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
