import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The always-present scoped search field, sitting in the breadcrumb row.
///
/// Searches recursively BELOW the pane's current folder, live. ⌘⇧F focuses it;
/// ⌘F is the separate global palette, because "find that file" is usually a
/// question about the whole machine while this one is explicitly "find it under
/// here".
///
/// Permanently visible rather than summoned: scoped search is the common case,
/// and hiding it behind a keystroke means most people never find it.
struct FilesFilterField: View {
    @Bindable var search: FilesSearchStore
    var isFocused: FocusState<Bool>.Binding

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Image(systemName: search.isScopedSearching ? "ellipsis" : "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(theme.foreground.opacity(search.isScoped ? 0.8 : 0.4))

            TextField("Search here", text: $search.scopedText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .focused(isFocused)
                .frame(width: 150)
                .onExitCommand {
                    search.clearScoped()
                    isFocused.wrappedValue = false
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
    }
}
