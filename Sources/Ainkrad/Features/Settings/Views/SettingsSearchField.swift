import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Search has three states. The palette answers "where is it?"; filtering is
/// what you get once you have gone somewhere with the query still live, and
/// it dims rather than hides so the page keeps its shape.
enum SettingsSearchMode: Equatable {
    case browsing
    case palette(String)
    case filtering(String)

    init(query: String, hasNavigated: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { self = .browsing }
        else if hasNavigated { self = .filtering(trimmed) }
        else { self = .palette(trimmed) }
    }

    var query: String? {
        switch self {
        case .browsing: return nil
        case .palette(let q), .filtering(let q): return q
        }
    }
}

/// The search field at the top of the sidebar. ⌘F focuses it.
struct SettingsSearchField: View {
    @Environment(\.ainkradTheme) private var tokens
    @Binding var query: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(AinkradFont.display(12))
                .foregroundStyle(tokens.foreground.opacity(0.9))
                .focused($isFocused)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.foreground.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(ChamferShape(cut: AinkradRadius.sm)
            .fill(tokens.surfaceElevated.opacity(isFocused ? 0.7 : 0.45)))
        .overlay(ChamferShape(cut: AinkradRadius.sm)
            .strokeBorder(tokens.accentPrimary.opacity(isFocused ? 0.45 : 0.15), lineWidth: 1))
    }
}
