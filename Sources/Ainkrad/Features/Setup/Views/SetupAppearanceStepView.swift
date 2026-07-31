import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Applies the Appearance step's choices to the live stores.
///
/// Order is load-bearing: `ThemeManager.setTheme` clears `accentColorHex`
/// (ThemeManager.swift:45), so the accent must be set afterwards or it is lost.
@MainActor
enum SetupAppearance {
    static func apply(theme: Theme, accentHex: String?,
                      family: UIFontFamily, scale: UIFontScale,
                      icon: AppIconChoice, iconAppearance: AppIconAppearance,
                      themeManager: ThemeManager, iconStore: AppIconStore) {
        themeManager.setTheme(theme)
        themeManager.setAccentColorHex(accentHex)
        themeManager.setFontFamily(family)
        themeManager.setFontScale(scale)
        iconStore.selectColor(icon)
        iconStore.selectAppearance(iconAppearance)
    }
}

/// The Appearance step: theme, accent, typography and app-icon controls,
/// each applying immediately to the live `ThemeManager` / `AppIconStore`.
///
/// ART DIRECTION — the preview is the app, so the app is what is framed.
///
/// The workspace is loaded and rendering behind the blur; that is the entire
/// reason this wizard runs after bootstrap. The earlier pass at this screen
/// still spent it on swatches: four all-caps section headers, each control
/// under a form label ("FONT SIZE", "COLOR"), which reads as a settings pane
/// that happens to be live. Someone reading a labelled grid looks AT the grid.
///
/// So this version does three things instead:
///
/// 1. A lead line that points AWAY from the controls — the one sentence on the
///    screen whose job is to move the user's eye past it, to the window behind.
///    It names what is back there (islands, sky, chrome), because a person who
///    has never seen this app does not yet know what to watch.
/// 2. The controls carry prose, not labels. "Theme" with a sentence saying the
///    whole workspace re-tints, not "THEME" over a grid. Sentence case, said
///    the way a person would say it.
/// 3. The groups stage in, one after another, through `SetupStageMotion` — so
///    the screen assembles rather than landing as a form. Flat under
///    reduce-motion, which the user may have just turned on one step later (and
///    may return here with Back).
///
/// What did NOT change, deliberately: the controls themselves are still the
/// shared kit's, matching `AppearanceSettingsView` component for component.
/// Art direction is framing and copy — inventing a wizard-only theme picker
/// would split one product into two visual languages for the same setting.
///
/// Controls that map onto a single store call (theme, font family/scale, icon
/// color/appearance) fire that setter directly. `SetupAppearance.apply` is not
/// used here: batching every control's current value through it on every change
/// would fight the "apply immediately, independently" model. It exists for the
/// *test* to pin the ordering trap on, not for the view to route through.
struct SetupAppearanceStepView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.setupGroupWidth) private var groupWidth

    let coordinator: SetupCoordinator

    /// Flipped once on appear to stage the groups in. Never reset — coming Back
    /// to this step re-mounts the view.
    @State private var hasSettled = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    lead(tokens: tokens)
                    group(index: 1,
                          title: "Theme",
                          hint: "The whole workspace re-tints — window, islands, and the sky "
                              + "behind this screen.",
                          tokens: tokens) {
                        themeGrid(tokens: tokens)
                    }
                    group(index: 2,
                          title: "Accent",
                          hint: "Used for anything live: selection, focus, the things that are "
                              + "currently doing something.",
                          tokens: tokens) {
                        accentColorRow(tokens: tokens, manager: environment.themeManager)
                    }
                    // "Type" first, which reads as a verb before it reads as a
                    // noun — an instruction to start typing, on a screen whose
                    // best line ("Look at the Dock") IS an instruction. Named
                    // for the two controls under it instead.
                    group(index: 3,
                          title: "Typeface and size",
                          hint: "Every word in the app, including the ones you are reading now.",
                          tokens: tokens) {
                        typographyControls(tokens: tokens)
                    }
                    group(index: 4,
                          title: "App icon",
                          hint: "Look at the Dock — it changes as you pick.",
                          tokens: tokens) {
                        appIconControls(tokens: tokens)
                    }
                }
                .padding(20)
                // FILLS the group, exactly as the Home step's folder listing
                // does. Capping the whole column instead left every panel hard
                // against the left edge with a void beside it — the layout read
                // as broken rather than as composed, because the empty space was
                // INSIDE the group rather than around it.
                //
                // Prose within the column is capped individually; see the
                // section hints.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { hasSettled = true }

            // Never blocking: every control here has a real default that is
            // already applied live, so there is nothing for the user to supply.
            SetupStepFooter(coordinator: coordinator) { coordinator.advance() }
        }
    }

    // MARK: - Lead

    /// The only sentence on this screen that is not attached to a control, and
    /// the only one that matters if the user reads nothing else: it says the
    /// thing behind the blur is the real app, already running.
    private func lead(tokens: DesignTokens) -> some View {
        staged(index: 0) {
            Text("Ainkrad is already running behind this screen — that is your workspace "
                 + "back there, not a picture of one. Nothing here needs saving: change "
                 + "something and watch it happen.")
                .font(AinkradFont.display(15))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                       alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Theme

    private func themeGrid(tokens: DesignTokens) -> some View {
        let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Theme.allCases, id: \.self) { theme in
                themeCard(theme, tokens: tokens)
            }
        }
    }

    private func themeCard(_ theme: Theme, tokens: DesignTokens) -> some View {
        let isSelected = environment.themeManager.currentTheme == theme
        let themeTokens = theme.tokens

        return Button {
            environment.themeManager.setTheme(theme)
        } label: {
            HStack(spacing: 11) {
                ChamferShape(cut: 7)
                    .fill(
                        LinearGradient(
                            colors: [themeTokens.accentPrimary, themeTokens.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(
                        ChamferShape(cut: 7)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    )

                Text(theme.displayName)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.7))

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                ChamferShape(cut: AinkradRadius.md)
                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accent

    /// Preset swatches (one per theme's accent) plus a color-well for
    /// anything else — the same pattern `AppearanceSettingsView` uses, so the
    /// wizard and Settings agree on how an accent is picked. A well over a
    /// palette-only picker is required here because the accent is a
    /// free-form 6-digit hex, not one of a fixed set — restricting the
    /// wizard to presets while Settings allows any color would be a
    /// regression the moment the user opens Settings afterward.
    private func accentColorRow(tokens: DesignTokens, manager: ThemeManager) -> some View {
        HStack(spacing: 9) {
            ForEach(Theme.allCases, id: \.self) { theme in
                accentSwatch(theme, tokens: tokens, manager: manager)
            }
            AinkradColorPicker(
                selection: Binding(
                    get: { manager.accentColorHex.map { Color(hex: $0) } ?? tokens.accentPrimary },
                    set: { manager.setAccentColorHex($0.hexString) }
                )
            )
            .frame(width: 30, height: 30)
            .help("Any other colour")
            .accessibilityLabel("Choose any other accent colour")
        }
    }

    /// One accent preset.
    ///
    /// Chamfered rather than round, to match the theme cards above it — the two
    /// rows were a grid of chamfers over a row of circles, which read as two
    /// unrelated controls rather than as one screen.
    ///
    /// The selected state also accounts for INHERITANCE. `accentColorHex` is nil
    /// until the user picks an accent explicitly, and the old check keyed only
    /// off that — so on arrival nothing was selected at all, even though the
    /// workspace visibly had an accent. It now shows the theme's own accent as
    /// the current one, which is what the user is actually looking at.
    private func accentSwatch(_ theme: Theme, tokens: DesignTokens,
                              manager: ThemeManager) -> some View {
        let color = theme.tokens.accentPrimary
        let hex = color.hexString
        let isExplicit = manager.accentColorHex == hex
        let isInherited = manager.accentColorHex == nil
            && manager.currentTheme.tokens.accentPrimary.hexString == hex
        let isSelected = isExplicit || isInherited

        return Button {
            manager.setAccentColorHex(hex)
        } label: {
            ChamferShape(cut: 7)
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    ChamferShape(cut: 7).strokeBorder(
                        isSelected ? tokens.foreground.opacity(0.95) : .white.opacity(0.16),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .overlay(
                    // A tick, not just a ring: at 30pt a 2pt ring alone is easy
                    // to miss, and this control has no other confirmation.
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityLabel("\(theme.displayName) accent")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Typography

    private func typographyControls(tokens: DesignTokens) -> some View {
        let manager = environment.themeManager
        return VStack(alignment: .leading, spacing: 9) {
            captioned("Typeface", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: UIFontFamily.allCases,
                    selection: Binding(get: { manager.uiFontFamily },
                                       set: { manager.setFontFamily($0) }),
                    label: fontFamilyTitle
                )
            }
            captioned("Size", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: UIFontScale.allCases,
                    selection: Binding(get: { manager.uiFontScale },
                                       set: { manager.setFontScale($0) }),
                    label: fontScaleTitle
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font family and size")
    }

    // MARK: - App icon

    private func appIconControls(tokens: DesignTokens) -> some View {
        let store = environment.appIconStore
        return VStack(alignment: .leading, spacing: 9) {
            captioned("Colour", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: AppIconChoice.allCases,
                    selection: Binding(get: { store.choice }, set: { store.selectColor($0) }),
                    label: iconColorTitle
                )
            }
            captioned("Light or dark", tokens: tokens) {
                AinkradSegmentedPicker(
                    items: AppIconAppearance.allCases,
                    selection: Binding(get: { store.appearance },
                                       set: { store.selectAppearance($0) }),
                    label: iconAppearanceTitle
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("App icon color and appearance")
    }

    /// A control with a caption in a fixed leading column.
    ///
    /// Both of the paired sections on this screen — typeface/size and icon
    /// colour/appearance — are TWO AXES, and rendering them as two identical
    /// rows of pills made them read as one flat list of six options. "Auto,
    /// Blue, Purple, System, Light, Dark" is unparseable without knowing where
    /// one control ends and the next begins.
    ///
    /// An earlier comment argued the contents said what they were. That is true
    /// of "Small / Medium / Large" and false of everything else here, and it is
    /// never true of the RELATIONSHIP between the two rows.
    ///
    /// The caption column is a fixed width so the two controls align down the
    /// screen, which is what makes them read as a form rather than as loose
    /// buttons.
    private func captioned<Content: View>(_ caption: String, tokens: DesignTokens,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(caption)
                .font(AinkradFont.display(11, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.45))
                .frame(width: 86, alignment: .leading)
                .accessibilityHidden(true)
            content()
            Spacer(minLength: 0)
        }
    }

    // MARK: - Group + staging

    /// One choice: a spoken title, a sentence saying what the user will see
    /// change, and the control. No all-caps header, no boxed card and no rule
    /// above it — the groups are separated by space alone, per the design
    /// language's no-separator rule.
    private func group<Content: View>(index: Int, title: String, hint: String,
                                      tokens: DesignTokens,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        staged(index: index) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AinkradFont.display(15, weight: .medium))
                        .foregroundStyle(tokens.foreground.opacity(0.95))
                    Text(hint)
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground.opacity(0.55))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        // Capped where the CONTROLS below are not: the column
                        // fills the group so the theme cards can use the room,
                        // but a one-line hint stretched to 1000pt is unreadable.
                        .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                               alignment: .leading)
                }

                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A recessed surface per section, exactly as the Home step draws its
            // folder listing. Without one, four sections of bare text and loose
            // controls float on the scrim with nothing but vertical space
            // separating them, and the screen reads as a settings dump rather
            // than as a composed step.
            //
            // Still no separator LINES — the surface is what does the dividing,
            // which is the design language's rule rather than an exception to it.
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(tokens.surfaceElevated.opacity(0.32))
            )
        }
    }

    /// The staging itself, routed through `SetupStageMotion` — never a bare
    /// `.animation(...)`. Under reduce-motion `layerGeometry` returns `nil` and
    /// `animation` returns `nil`, so there is no lift, no stagger and nothing
    /// to fade from: the group is simply present.
    ///
    /// `isForward: true` is not a direction claim — the stage already owns
    /// directional entry for the step as a whole. It is asked in the forward
    /// orientation purely to take the magnitude and the reduce-motion gate,
    /// the same way `SetupHomeStepView` does for its folder rows.
    private func staged<Content: View>(index: Int,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        let geometry = SetupStageMotion.layerGeometry(.content,
                                                      reduceMotion: reduceMotion,
                                                      isForward: true)
        let lift = geometry.map { $0.lift * 0.6 } ?? 0
        // ONLY the per-index stagger — `SetupStageMotion.animation(layer:)`
        // already carries `.content`'s own 0.11s delay, and adding
        // `geometry.delay` to it double-counted, holding the first group off
        // screen for 0.22s. `geometry` is still consulted because `nil` is the
        // reduce-motion seam.
        let delay = geometry.map { _ in Double(index) * 0.06 } ?? 0

        return content()
            .opacity(hasSettled ? 1 : 0)
            .offset(y: hasSettled ? 0 : lift)
            .animation(SetupStageMotion.animation(reduceMotion: reduceMotion,
                                                  layer: .content)?.delay(delay),
                       value: hasSettled)
    }

    // MARK: - Titles

    private func fontScaleTitle(_ scale: UIFontScale) -> String {
        switch scale { case .small: return "Small"; case .medium: return "Medium"; case .large: return "Large" }
    }

    private func fontFamilyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    private func iconColorTitle(_ c: AppIconChoice) -> String {
        switch c { case .auto: return "Auto"; case .blue: return "Blue"; case .purple: return "Purple" }
    }

    private func iconAppearanceTitle(_ a: AppIconAppearance) -> String {
        switch a { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
}
