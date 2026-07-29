import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// The ranked result list that replaces the detail pane while searching.
/// Each row shows the field, where it lives, and its current value — the
/// value is often the whole reason for the search.
struct SettingsPaletteView: View {
    @Environment(\.ainkradTheme) private var tokens
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    let results: [SettingsSearchResult]
    let query: String
    let onSelect: (SettingsPath) -> Void

    @State private var highlightedIndex = 0

    var body: some View {
        if results.isEmpty {
            AinkradEmptyState(
                icon: "magnifyingglass",
                title: "No settings match \u{201C}\(query)\u{201D}",
                message: "Try a shorter word, or the name of the app the setting belongs to.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        row(result, isHighlighted: index == highlightedIndex)
                    }
                }
                .padding(18)
            }
            .scrollContentBackground(.hidden)
            .onKeyPress(.downArrow) {
                highlightedIndex = min(highlightedIndex + 1, results.count - 1); return .handled
            }
            .onKeyPress(.upArrow) {
                highlightedIndex = max(highlightedIndex - 1, 0); return .handled
            }
            .onKeyPress(.return) {
                onSelect(results[highlightedIndex].path); return .handled
            }
            .onChange(of: query) { _, _ in highlightedIndex = 0 }
        }
    }

    private func row(_ result: SettingsSearchResult, isHighlighted: Bool) -> some View {
        Button { onSelect(result.path) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.label)
                        .font(AinkradFont.display(13, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.92))
                    Text(result.breadcrumb)
                        .font(AinkradFont.mono(10))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                }
                Spacer(minLength: 12)
                if let value = result.valueDescription {
                    Text(value)
                        .font(AinkradFont.mono(11))
                        .foregroundStyle(tokens.accentSecondary.opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(ChamferShape(cut: AinkradRadius.md)
                .fill(isHighlighted ? tokens.accentPrimary.opacity(0.14) : tokens.surfaceElevated.opacity(0.4)))
            .overlay(TargetingBrackets(length: 7)
                .stroke(isHighlighted ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.3)
                .padding(1))
            .settingsRowHover(isActive: isHighlighted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHighlighted)
    }
}
