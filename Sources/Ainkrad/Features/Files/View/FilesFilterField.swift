import SwiftUI
import AinkradAppKit
import AinkradAppKitUI

/// The always-present in-folder filter, sitting in the breadcrumb row.
///
/// Permanently visible rather than summoned with `/`: filtering the folder you
/// are looking at is the common case, and hiding it behind a keystroke means
/// most people never find it. `/` still focuses it, for the people who do.
struct FilesFilterField: View {
    @Bindable var search: FilesSearchStore
    var isFocused: FocusState<Bool>.Binding

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: AinkradSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(theme.foreground.opacity(search.isFiltering ? 0.8 : 0.4))

            TextField("Filter", text: $search.filterText)
                .textFieldStyle(.plain)
                .font(AinkradFontResolver.font(.caption, typography: typo))
                .focused(isFocused)
                .frame(width: 130)
                .onExitCommand {
                    search.clearFilter()
                    isFocused.wrappedValue = false
                }

            if search.isFiltering {
                Button {
                    search.clearFilter()
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
                .fill(theme.foreground.opacity(search.isFiltering ? 0.10 : 0.06))
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: search.isFiltering)
    }
}
