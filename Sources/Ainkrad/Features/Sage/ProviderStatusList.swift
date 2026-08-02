import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// A named endpoint preset for the Custom provider (label → base URL). Picking
/// one prefills the custom base URL, so many OpenAI-compatible providers are
/// reachable by name without a bespoke backend each.
struct EndpointPreset: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let baseURL: String
}

/// Tappable chips that fill the Custom endpoint's base URL from a named preset.
struct ProviderPresetChips: View {
    let presets: [EndpointPreset]
    let tokens: DesignTokens
    let onPick: (EndpointPreset) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(presets) { preset in
                Text(preset.label)
                    .font(AinkradFont.display(10, weight: .medium))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(ChamferShape(cut: 5).fill(tokens.surfaceElevated.opacity(0.4)))
                    .overlay(ChamferShape(cut: 5).strokeBorder(tokens.accentSecondary.opacity(0.3), lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(preset) }
            }
        }
    }
}

/// Minimal wrapping HStack so preset chips flow onto multiple lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One selectable provider row's data.
struct ProviderOption: Identifiable, Equatable {
    let id: String
    let label: String
    /// Configured = ready to use (has its key/URL, or is keyless).
    let configured: Bool
    /// Keyless providers never need credentials.
    let keyless: Bool
}

/// A provider-management surface: a list of providers with a status dot
/// (green = configured/ready, amber = needs setup), the active/default one
/// highlighted with a check. Tapping a row makes it the default. Replaces the
/// flat dropdown so status and selection live in one place. Zero native controls
/// (chamfer rows + `onTapGesture`, no `Button`/`Picker`).
struct ProviderStatusList: View {
    let options: [ProviderOption]
    @Binding var selection: String
    let tokens: DesignTokens
    var onSelect: ((String) -> Void)? = nil

    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 5) {
            ForEach(options) { option in
                row(option)
            }
        }
    }

    private func row(_ option: ProviderOption) -> some View {
        let isSelected = option.id == selection
        return HStack(spacing: 9) {
            Circle()
                .fill(option.configured ? tokens.success : tokens.warning)
                .frame(width: 7, height: 7)
                .shadow(color: (option.configured ? tokens.success : tokens.warning).opacity(0.6), radius: 3)
            Text(option.label)
                .font(AinkradFont.display(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.75))
            Spacer(minLength: 6)
            Text(option.keyless ? "keyless" : (option.configured ? "ready" : "needs key"))
                .font(AinkradFont.mono(9))
                .foregroundStyle(tokens.foreground.opacity(0.4))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tokens.accentSecondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(ChamferShape(cut: 6).fill(tokens.surfaceElevated.opacity(isSelected ? 0.5 : 0.25)))
        .overlay(ChamferShape(cut: 6).strokeBorder(
            (isSelected ? tokens.accentPrimary : tokens.foreground).opacity(isSelected ? 0.5 : 0.12), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = option.id
            onSelect?(option.id)
        }
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: isSelected)
    }
}
