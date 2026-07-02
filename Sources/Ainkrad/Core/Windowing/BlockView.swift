import SwiftUI

/// One Block: a thin header (icon, title, close ×) flush above its hosted
/// app content — no floating chrome, drop shadow, or z-order. See
/// Window & Tile Management Architecture.md.
struct BlockView: View {
    @Environment(AppEnvironment.self) private var environment
    let block: Block
    let tileLayout: TileLayout
    let registry: BuiltInAppRegistry

    private var app: BuiltInApp.Type? {
        registry.allApps.first { $0.id == block.appID }
    }

    private var isFocused: Bool {
        tileLayout.focusedBlockID == block.id
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            header(tokens: tokens)
            Divider()
            content(tokens: tokens)
        }
        .background(tokens.surface)
        .overlay(
            Rectangle()
                .strokeBorder(
                    isFocused ? tokens.accentPrimary.opacity(0.7) : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { tileLayout.focus(block.id) }
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 6) {
            if let app {
                Image(systemName: app.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isFocused ? tokens.accentPrimary : tokens.foreground.opacity(0.5))
                Text(app.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isFocused ? tokens.foreground : tokens.foreground.opacity(0.6))
            }
            Spacer()
            Button {
                tileLayout.close(block.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isFocused ? tokens.surfaceElevated : tokens.surface)
    }

    @ViewBuilder
    private func content(tokens: DesignTokens) -> some View {
        if let app {
            app.makeRootView()
        } else {
            tokens.surface
        }
    }
}
