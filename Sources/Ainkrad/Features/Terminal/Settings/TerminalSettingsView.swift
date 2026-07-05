import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AinkradAppKit

/// Terminal's per-app settings, hosted in the Settings overlay's Terminal
/// section: Appearance (color scheme + font) and Behavior (default shell +
/// working directory). Edits route through `TerminalSettingsStore`, so they
/// persist immediately and restyle running terminals live — see Terminal App
/// Architecture.md and Navigation & Settings Architecture.md.
struct TerminalSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var shellPathText = ""
    @State private var shellValidationMessage: String?
    @State private var isChoosingFolder = false
    @State private var isLoaded = false

    private var availableFonts: [String] { MonospacedFonts.available() }

    private var settings: TerminalSettings { environment.terminalSettingsStore.settings }

    private var resolved: TerminalRenderAppearance {
        TerminalAppearanceResolver.resolve(settings: settings, tokens: HostThemeTokens(from: environment.themeManager.currentTheme))
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                appearanceSection(tokens: tokens)
                behaviorSection(tokens: tokens)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: loadIfNeeded)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            environment.terminalSettingsStore.update { $0.defaultWorkingDirectory = url }
        }
    }

    // MARK: - Appearance

    private func appearanceSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "APPEARANCE", tokens: tokens)

            Text("Color Scheme")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(TerminalColorScheme.all) { scheme in
                    schemeCard(scheme, tokens: tokens)
                }
            }

            HStack(spacing: 16) {
                fontFamilyControl(tokens: tokens)
                fontSizeControl(tokens: tokens)
            }
            .padding(.top, 4)

            cursorControls(tokens: tokens)

            HStack(spacing: 16) {
                colorControl(
                    label: "Cursor Color",
                    override: settings.cursorColor,
                    resolvedHex: resolved.cursor,
                    tokens: tokens
                ) { newHex in environment.terminalSettingsStore.update { $0.cursorColor = newHex } }

                colorControl(
                    label: "Selection Color",
                    override: settings.selectionColor,
                    resolvedHex: resolved.selection,
                    tokens: tokens
                ) { newHex in environment.terminalSettingsStore.update { $0.selectionColor = newHex } }
            }

            transparencyControl(tokens: tokens)
        }
    }

    private func transparencyControl(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Background Transparency")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Spacer()
                Text("\(Int((1 - settings.backgroundOpacity) * 100))%")
                    .font(AinkradFont.mono(11))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.8))
            }
            Slider(
                value: Binding(
                    get: { settings.backgroundOpacity },
                    set: { v in environment.terminalSettingsStore.update { $0.backgroundOpacity = v } }
                ),
                in: 0.2...1.0
            )
            .tint(tokens.accentPrimary)
            Text("Lets the ambient backdrop show through the terminal.")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.45))
        }
        .padding(.top, 2)
    }

    private func cursorControls(tokens: DesignTokens) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cursor")
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                HStack(spacing: 4) {
                    ForEach(TerminalCursorShape.allCases, id: \.self) { shape in
                        cursorShapeButton(shape, tokens: tokens)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Blink")
                    .font(AinkradFont.display(12))
                    .foregroundStyle(tokens.foreground.opacity(0.7))
                NeonToggle(
                    isOn: Binding(
                        get: { settings.cursorBlink },
                        set: { v in environment.terminalSettingsStore.update { $0.cursorBlink = v } }
                    ),
                    tokens: tokens
                )
            }
            .padding(.bottom, 5)
        }
    }

    private func cursorShapeButton(_ shape: TerminalCursorShape, tokens: DesignTokens) -> some View {
        let isSelected = settings.cursorShape == shape
        let icon: String = switch shape {
        case .block: "rectangle.fill"
        case .underline: "underline"
        case .bar: "cursorarrow.click"
        }
        return Button {
            environment.terminalSettingsStore.update { $0.cursorShape = shape }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? tokens.foreground : tokens.foreground.opacity(0.5))
                .frame(width: 40, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? tokens.accentPrimary.opacity(0.18) : tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? tokens.accentPrimary.opacity(0.5) : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shape.rawValue.capitalized)
    }

    private func colorControl(
        label: String,
        override: String?,
        resolvedHex: String,
        tokens: DesignTokens,
        set: @escaping (String?) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            HStack(spacing: 8) {
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(hex: override ?? resolvedHex) },
                        set: { set($0.hexString) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                if override != nil {
                    Button("Reset") { set(nil) }
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.accentSecondary)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func schemeCard(_ scheme: TerminalColorScheme, tokens: DesignTokens) -> some View {
        let isSelected = settings.colorSchemeID == scheme.id
        let preview = TerminalAppearanceResolver.resolve(
            settings: TerminalSettings(colorSchemeID: scheme.id),
            tokens: HostThemeTokens(from: environment.themeManager.currentTheme)
        )

        return Button {
            environment.terminalSettingsStore.update { $0.colorSchemeID = scheme.id }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Miniature terminal preview.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: preview.background))
                    .frame(height: 40)
                    .overlay(
                        HStack(spacing: 3) {
                            Text(">")
                                .foregroundStyle(Color(hex: preview.cursor))
                            Text("ainkrad")
                                .foregroundStyle(Color(hex: preview.foreground))
                        }
                        .font(AinkradFont.mono(10))
                        .padding(.horizontal, 8),
                        alignment: .leading
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )

                Text(scheme.name)
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.65))
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.13) : tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tokens.accentPrimary.opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
            )
            .overlay(
                TargetingBrackets(length: 9)
                    .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.4)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private func fontFamilyControl(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Font")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))

            Menu {
                ForEach(availableFonts, id: \.self) { family in
                    Button(family) {
                        environment.terminalSettingsStore.update { $0.fontFamily = family }
                    }
                }
            } label: {
                HStack {
                    Text(settings.fontFamily ?? TerminalAppearanceResolver.defaultFontFamily)
                        .font(AinkradFont.display(12))
                        .foregroundStyle(tokens.foreground)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(tokens.foreground.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .frame(width: 200, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func fontSizeControl(tokens: DesignTokens) -> some View {
        let size = settings.fontSize ?? TerminalAppearanceResolver.defaultFontSize

        return VStack(alignment: .leading, spacing: 6) {
            Text("Size")
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))

            HStack(spacing: 0) {
                stepperButton("minus", tokens: tokens) {
                    environment.terminalSettingsStore.update { $0.fontSize = max(9, size - 1) }
                }
                Text("\(Int(size))")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground)
                    .frame(width: 34)
                stepperButton("plus", tokens: tokens) {
                    environment.terminalSettingsStore.update { $0.fontSize = min(28, size + 1) }
                }
            }
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tokens.surfaceElevated.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func stepperButton(_ icon: String, tokens: DesignTokens, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tokens.accentSecondary)
                .frame(width: 30, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Behavior

    private func behaviorSection(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "BEHAVIOR", tokens: tokens)

            field(label: "Default Shell", tokens: tokens) {
                TextField("/bin/zsh", text: $shellPathText)
                    .textFieldStyle(.plain)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground)
                    .tint(tokens.accentSecondary)
                    .onSubmit(updateShell)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                    )

                if let shellValidationMessage {
                    Text(shellValidationMessage)
                        .font(AinkradFont.display(11))
                        .foregroundStyle(Color(hex: "E5484D"))
                } else {
                    Text("Must be listed in /etc/shells. Leave empty to use the login shell.")
                        .font(AinkradFont.display(11))
                        .foregroundStyle(tokens.foreground.opacity(0.45))
                }
            }

            field(label: "Default Working Directory", tokens: tokens) {
                HStack(spacing: 10) {
                    Text(settings.defaultWorkingDirectory?.path ?? "Home directory")
                        .font(AinkradFont.mono(12))
                        .foregroundStyle(tokens.foreground.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if settings.defaultWorkingDirectory != nil {
                        Button {
                            environment.terminalSettingsStore.update { $0.defaultWorkingDirectory = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(tokens.foreground.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help("Reset to home directory")
                    }

                    Button("Choose…") { isChoosingFolder = true }
                        .font(AinkradFont.display(12, weight: .medium))
                        .foregroundStyle(tokens.accentSecondary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                )
            }

            toggleRow(
                label: "Use Option as Meta key",
                help: "Send ⌥ as Meta/Esc+ (for tmux, emacs, and shell editing).",
                isOn: Binding(
                    get: { settings.optionAsMeta },
                    set: { v in environment.terminalSettingsStore.update { $0.optionAsMeta = v } }
                ),
                tokens: tokens
            )

            toggleRow(
                label: "Send mouse events to apps",
                help: "Forward clicks, motion, and the wheel to terminal apps (Claude Code, vim, tmux). Off: mouse stays for native selection and scrollback.",
                isOn: Binding(
                    get: { settings.sendMouseEventsToApps },
                    set: { v in environment.terminalSettingsStore.update { $0.sendMouseEventsToApps = v } }
                ),
                tokens: tokens
            )

            field(label: "Scrollback Lines", tokens: tokens) {
                HStack(spacing: 0) {
                    stepperButton("minus", tokens: tokens) {
                        environment.terminalSettingsStore.update { $0.scrollbackLines = max(0, $0.scrollbackLines - 500) }
                    }
                    Text("\(settings.scrollbackLines)")
                        .font(AinkradFont.mono(12))
                        .foregroundStyle(tokens.foreground)
                        .frame(width: 64)
                    stepperButton("plus", tokens: tokens) {
                        environment.terminalSettingsStore.update { $0.scrollbackLines = min(100_000, $0.scrollbackLines + 500) }
                    }
                }
                .frame(width: 124, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    private func toggleRow(label: String, help: String, isOn: Binding<Bool>, tokens: DesignTokens) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.85))
                Text(help)
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            NeonToggle(isOn: isOn, tokens: tokens)
        }
    }

    private func field<Content: View>(
        label: String,
        tokens: DesignTokens,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            content()
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        shellPathText = settings.defaultShell ?? ""
    }

    private func updateShell() {
        let trimmed = shellPathText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            environment.terminalSettingsStore.update { $0.defaultShell = nil }
            shellValidationMessage = nil
            return
        }

        do {
            _ = try ShellResolver().resolveDefaultShell(override: trimmed)
            environment.terminalSettingsStore.update { $0.defaultShell = trimmed }
            shellValidationMessage = nil
        } catch {
            shellValidationMessage = "Not a shell listed in /etc/shells."
        }
    }
}
