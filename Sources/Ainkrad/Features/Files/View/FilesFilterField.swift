import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The always-present scoped search field, sitting in the breadcrumb row.
///
/// Searches recursively BELOW the pane's current folder, live. ⌥F focuses it;
/// ⌘F is the separate global palette, because "find that file" is usually a
/// question about the whole machine while this one is explicitly "find it under
/// here". (⌥F rather than ⌘⇧F: that chord is claimed above the app and never
/// arrives — see `FilesKeyMonitor`.)
///
/// Permanently visible rather than summoned: scoped search is the common case,
/// and hiding it behind a keystroke means most people never find it.
struct FilesFilterField: View {
    @Bindable var search: FilesSearchStore

    /// Owned here, not passed in. See `FilesSearchStore.focusRequests`.
    @FocusState private var focused: Bool

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Image(systemName: search.isScopedSearching ? "ellipsis" : "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(theme.foreground.opacity(search.isScoped ? 0.8 : 0.4))

            TextField("Search here  ⌥F", text: $search.scopedText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .focused($focused)
                .frame(width: 150)
                .onExitCommand {
                    search.clearScoped()
                    focused = false
                }

            if search.isScoped {
                Button {
                    search.clearScoped()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.foreground.opacity(0.45))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AinkradSpacing.sm)
        .padding(.vertical, 3)
        .background(
            ChamferShape(cut: 4)
                .fill(theme.foreground.opacity(search.isScoped ? 0.10 : 0.06))
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: search.isScoped)
        .onChange(of: search.focusRequests) { _, _ in focused = true }
        // `onChange` does not fire for the value a view is BORN with, so a
        // request that arrives in the same render pass that creates this field
        // would otherwise be dropped.
        .onAppear { if search.focusRequests > 0 { focused = true } }
        // A visible focus ring: without it, ⌘⇧F looks like it did nothing even
        // when the caret is sitting in the field.
        .overlay(
            ChamferShape(cut: 4)
                .strokeBorder(theme.accentSecondary.opacity(focused ? 0.7 : 0), lineWidth: 1)
        )
    }
}
