import SwiftUI
import AinkradAppKit
import AinkradAppKitUI
import AinkradHostRuntime

/// What a transient message is telling you.
enum FilesToastKind: Equatable {
    case copied
    case cut
    case moved
    case deleted
    case created
    case undone
    case warning
    case failure

    var symbol: String {
        switch self {
        case .copied: return "doc.on.doc.fill"
        case .cut: return "scissors"
        case .moved: return "arrow.right.doc.on.clipboard"
        case .deleted: return "trash.fill"
        case .created: return "folder.fill.badge.plus"
        case .undone: return "arrow.uturn.backward"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    var isProblem: Bool { self == .warning || self == .failure }
}

struct FilesToastMessage: Equatable, Identifiable {
    let id = UUID()
    var kind: FilesToastKind
    var text: String
    /// Secondary line — the undo hint, or the failure detail.
    var detail: String?
}

/// Transient confirmation, in the Cardinal HUD language.
///
/// The first cut used `AinkradBanner`, a full-width bar that read as an error
/// strip for what is usually a success. This is a compact capsule: an accent
/// glyph, the message, and — the part that actually matters — the undo hint,
/// so "Copied 3 items" also tells you it is reversible.
struct FilesToast: View {
    let message: FilesToastMessage
    let onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var statusColors
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var tokens: DesignTokens { environment.themeManager.tokens }

    private var accent: Color {
        switch message.kind {
        case .failure: return statusColors.danger
        case .warning: return statusColors.warning
        default: return tokens.accentSecondary
        }
    }

    var body: some View {
        HStack(spacing: AinkradSpacing.md) {
            // Glyph in a tinted chamfer chip — the same treatment as
            // `AinkradIconGlyph`, so it reads as part of the kit.
            Image(systemName: message.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 22, height: 22)
                .background(ChamferShape(cut: 5).fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 1) {
                Text(message.text)
                    .font(AinkradFontResolver.font(.body, weight: .medium, typography: typo))
                    .foregroundStyle(tokens.foreground)
                if let detail = message.detail {
                    Text(detail)
                        .font(AinkradFontResolver.font(.caption, typography: typo))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.leading, AinkradSpacing.xs)
        }
        .padding(.horizontal, AinkradSpacing.md)
        .padding(.vertical, AinkradSpacing.sm)
        .background {
            ZStack {
                ChamferShape(cut: 8).fill(tokens.surfaceElevated.opacity(0.96))
                // A leading accent rule rather than a full tinted fill: colour
                // the meaning, not the whole surface.
                HStack(spacing: 0) {
                    Rectangle().fill(accent).frame(width: 2)
                    Spacer()
                }
                .clipShape(ChamferShape(cut: 8))
            }
        }
        .overlay(
            ChamferShape(cut: 8)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .ainkradPanelGlow()
        .fixedSize()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
                   value: message.id)
    }
}
