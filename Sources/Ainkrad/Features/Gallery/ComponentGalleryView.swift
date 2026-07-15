#if DEBUG
import SwiftUI
import AinkradAppKit

/// DEBUG-only design-system showcase: every SDK scale + component, rendered
/// across all 7 themes via a local theme switcher. Reachable from the
/// Launcher's "Component Gallery" system action (⌘K). Never compiled into a
/// release build — see `AppEnvironment.isComponentGalleryPresented` and
/// `LauncherView`'s `galleryRowID`.
///
/// The theme switcher drives its OWN `@State`, applied only to this view's
/// subtree via `.environment(\.ainkradTheme, …)` — switching it here never
/// touches `ThemeManager.currentTheme`, so the app's real theme (and every
/// other surface) is unaffected.
struct ComponentGalleryView: View {
    let onDismiss: () -> Void

    @State private var galleryTheme: Theme = .neonBlue
    @State private var toggleOn = true
    @State private var secureText = "sk-••••••••"
    @State private var textFieldText = "Sample text"
    @State private var sliderValue = 0.6
    @State private var pickerSelection = 0
    @State private var menuSelection = "Option A"
    @State private var scanlineOn = true
    @State private var hexGridOn = true
    @State private var glowBloomOn = true
    @State private var wave2ToggleOn = true
    @State private var wave2Chips = ["Removable", "Draft"]

    private var galleryTokens: HostThemeTokens { HostThemeTokens(from: galleryTheme) }
    private var galleryStatusColors: AinkradStatusColors {
        AinkradStatusColors(
            success: galleryTheme.tokens.success,
            warning: galleryTheme.tokens.warning,
            danger: galleryTheme.tokens.danger
        )
    }
    private var galleryTypography: AinkradTypography { .default }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(OverlayChrome.backdropOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                panel
                    .frame(
                        width: min(max(760, geo.size.width * 0.7), 980),
                        height: min(max(560, geo.size.height * 0.85), 780)
                    )
            }
        }
        // Local-only override — does NOT touch `environment.themeManager`.
        .environment(\.ainkradTheme, galleryTokens)
        .environment(\.ainkradStatusColors, galleryStatusColors)
        .environment(\.ainkradTypography, galleryTypography)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            themeSwitcher
            ScrollView {
                VStack(alignment: .leading, spacing: AinkradSpacing.xl) {
                    foundationSection
                    scalesSection
                    panelSection
                    cardSection
                    pickersSection
                    formControlsSection
                    stateViewsSection
                    sectionHeaderSection
                    wave2Section
                }
                .padding(AinkradSpacing.lg)
            }
        }
        .ainkradPanel()
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "swatchpalette")
                .foregroundStyle(galleryTokens.accentSecondary)
            Text("COMPONENT GALLERY")
                .font(AinkradFontResolver.font(.headline, weight: .semibold, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.9))
            Spacer()
            Text("esc")
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.4))
        }
        .padding(.horizontal, AinkradSpacing.lg)
        .frame(height: 52)
    }

    private var themeSwitcher: some View {
        AinkradSegmentedPicker(items: Theme.allCases, selection: $galleryTheme) { $0.displayName }
            .padding(.horizontal, AinkradSpacing.lg)
            .padding(.bottom, AinkradSpacing.sm)
    }

    // MARK: - Sections

    private var foundationSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Foundation", subtitle: "Chamfer, brackets, accent rule, effects, status colors")

            HStack(spacing: AinkradSpacing.md) {
                ChamferShape()
                    .fill(galleryTokens.surfaceElevated)
                    .frame(width: 120, height: 80)
                    .cornerBrackets()
            }

            AccentRule(label: "Accent Rule")

            HStack(spacing: AinkradSpacing.md) {
                VStack(spacing: 4) {
                    effectSamplePanel.scanlineOverlay(active: scanlineOn)
                    Toggle("Scanline", isOn: $scanlineOn)
                        .toggleStyle(.checkbox)
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.hexGridBackground(active: hexGridOn)
                    Toggle("Hex Grid", isOn: $hexGridOn)
                        .toggleStyle(.checkbox)
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }

                VStack(spacing: 4) {
                    effectSamplePanel.glowBloom(active: glowBloomOn)
                    Toggle("Glow Bloom", isOn: $glowBloomOn)
                        .toggleStyle(.checkbox)
                        .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground.opacity(0.7))
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                statusSwatch(label: "Success", color: galleryTheme.tokens.success)
                statusSwatch(label: "Warning", color: galleryTheme.tokens.warning)
                statusSwatch(label: "Danger", color: galleryTheme.tokens.danger)
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    private var effectSamplePanel: some View {
        RoundedRectangle(cornerRadius: AinkradRadius.sm)
            .fill(galleryTokens.surface)
            .frame(width: 96, height: 64)
    }

    private func statusSwatch(label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(color)
                .frame(width: 64, height: 32)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    private var scalesSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Scales", subtitle: "Spacing, radius, elevation, type roles")

            HStack(spacing: AinkradSpacing.sm) {
                ForEach(spacingSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(galleryTokens.accentPrimary.opacity(0.6))
                            .frame(width: sample.value, height: 12)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.md) {
                ForEach(radiusSamples, id: \.label) { sample in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: sample.value)
                            .fill(galleryTokens.surfaceElevated)
                            .frame(width: 48, height: 32)
                        Text(sample.label)
                            .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                            .foregroundStyle(galleryTokens.foreground.opacity(0.6))
                    }
                }
            }

            HStack(spacing: AinkradSpacing.lg) {
                elevationSample(label: "level0", shadow: AinkradElevation.level0)
                elevationSample(label: "level1", shadow: AinkradElevation.level1)
                elevationSample(label: "level2", shadow: AinkradElevation.level2)
            }
            .padding(.top, AinkradSpacing.sm)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AinkradTypeRole.allCases, id: \.self) { role in
                    Text("\(String(describing: role)) — \(Int(role.size))pt")
                        .font(AinkradFontResolver.font(role, typography: galleryTypography))
                        .foregroundStyle(galleryTokens.foreground)
                }
            }
            .padding(.top, AinkradSpacing.sm)
        }
    }

    private var panelSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Panel")
            AinkradPanel {
                Text("AinkradPanel content")
                    .font(AinkradFontResolver.font(.body, typography: galleryTypography))
                    .foregroundStyle(galleryTokens.foreground)
                    .padding(AinkradSpacing.lg)
            }
            .frame(height: 80)
        }
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Card", subtitle: "Default, hover-capable, selected")
            HStack(spacing: AinkradSpacing.md) {
                AinkradCard {
                    cardLabel("Default")
                }
                AinkradCard(onTap: {}) {
                    cardLabel("Interactive")
                }
                AinkradCard(isSelected: true) {
                    cardLabel("Selected")
                }
            }
        }
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var pickersSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Pickers")
            AinkradSegmentedPicker(items: Array(0..<3), selection: $pickerSelection) { "Item \($0)" }
            AinkradMenuPicker(items: ["Option A", "Option B", "Option C"], selection: $menuSelection) { $0 }
        }
    }

    private var formControlsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Form Controls")
            AinkradFormRow(title: "Enable feature", help: "A toggle in a form row") {
                AinkradToggle(isOn: $toggleOn)
            }
            AinkradTextField(text: $textFieldText, placeholder: "Text field")
            AinkradSecureField(text: $secureText, placeholder: "Secure field")
            AinkradSlider(value: $sliderValue, in: 0...1)
        }
    }

    private var stateViewsSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "State Views")
            HStack(spacing: AinkradSpacing.md) {
                AinkradEmptyState(icon: "tray", title: "Nothing here", message: "No items yet.",
                                  actionTitle: "Add Item", action: {})
                    .frame(height: 180)
                AinkradLoadingState(label: "Loading…")
                    .frame(height: 180)
                AinkradErrorState(message: "Something went wrong.", retryTitle: "Retry", retry: {})
                    .frame(height: 180)
            }
        }
    }

    private var sectionHeaderSection: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Section Header", subtitle: "Uppercased caption label, no separator line")
        }
    }

    // MARK: - Wave 2: Surfaces · Buttons · Type

    private var wave2Section: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.md) {
            AinkradSectionHeader(title: "Surfaces · Buttons · Type", subtitle: "Wave-2 Cardinal HUD components")

            wave2SurfacesRow
            wave2SectionFrameSample
            wave2ButtonsRow
            wave2TagsRow
            wave2TypeRow
        }
    }

    private var wave2SurfacesRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Panel (default / bracketed) & Card (default / interactive / selected)")
            HStack(alignment: .top, spacing: AinkradSpacing.md) {
                AinkradPanel {
                    wave2SampleText("Panel")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradPanel(showsBrackets: true) {
                    wave2SampleText("Panel + brackets")
                        .padding(AinkradSpacing.lg)
                }
                .frame(width: 140, height: 80)

                AinkradCard {
                    wave2SampleText("Default")
                }
                AinkradCard(onTap: {}) {
                    wave2SampleText("Hover-capable")
                }
                AinkradCard(isSelected: true) {
                    wave2SampleText("Selected")
                }
            }
        }
    }

    private func wave2SampleText(_ text: String) -> some View {
        Text(text)
            .font(AinkradFontResolver.font(.body, typography: galleryTypography))
            .foregroundStyle(galleryTokens.foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var wave2SectionFrameSample: some View {
        AinkradSectionFrame(title: "Section Frame") {
            AinkradLabel("Framed content sample", systemName: "square.stack.3d.up")
        }
    }

    private var wave2ButtonsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Buttons — all 4 styles, icon button, toggle button")
            HStack(spacing: AinkradSpacing.md) {
                AinkradButton(title: "Primary", style: .primary, action: {})
                AinkradButton(title: "Secondary", style: .secondary, action: {})
                AinkradButton(title: "Ghost", style: .ghost, action: {})
                AinkradButton(title: "Danger", style: .danger, action: {})
                AinkradIconButton(systemName: "bolt.fill", action: {})
                AinkradToggleButton(isOn: $wave2ToggleOn, systemName: "power", title: "Latch")
            }
        }
    }

    private var wave2TagsRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Chips, badges (all statuses), keyboard shortcuts")
            HStack(spacing: AinkradSpacing.md) {
                AinkradChip(label: "Removable", systemName: "tag", onRemove: {
                    wave2Chips.removeAll { $0 == "Removable" }
                })
                AinkradChip(label: "Static")
            }
            HStack(spacing: AinkradSpacing.sm) {
                ForEach(AinkradStatus.allCases, id: \.self) { status in
                    AinkradBadge(text: String(describing: status), status: status)
                }
            }
            HStack(spacing: AinkradSpacing.xs) {
                AinkradKbd("⌘")
                AinkradKbd("⇧")
                AinkradKbd("K")
            }
        }
    }

    private var wave2TypeRow: some View {
        VStack(alignment: .leading, spacing: AinkradSpacing.sm) {
            AinkradCaption("Label & Caption")
            AinkradLabel("Sample label text", systemName: "text.alignleft")
            AinkradCaption("Sample dimmed caption text")
        }
    }

    private func elevationSample(label: String, shadow: ShadowSpec) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: AinkradRadius.sm)
                .fill(galleryTokens.surfaceElevated)
                .frame(width: 64, height: 40)
                .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            Text(label)
                .font(AinkradFontResolver.font(.caption, typography: galleryTypography))
                .foregroundStyle(galleryTokens.foreground.opacity(0.6))
        }
    }

    private var spacingSamples: [(label: String, value: CGFloat)] {
        [("xs", AinkradSpacing.xs), ("sm", AinkradSpacing.sm), ("md", AinkradSpacing.md),
         ("lg", AinkradSpacing.lg), ("xl", AinkradSpacing.xl), ("xxl", AinkradSpacing.xxl)]
    }

    private var radiusSamples: [(label: String, value: CGFloat)] {
        [("sm", AinkradRadius.sm), ("md", AinkradRadius.md), ("lg", AinkradRadius.lg), ("panel", AinkradRadius.panel)]
    }
}
#endif
