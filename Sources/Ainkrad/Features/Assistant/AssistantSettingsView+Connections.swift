import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

extension AssistantSettingsView {
    // MARK: - Connections

    func connectionsSection(tokens: DesignTokens) -> some View {
        let store = environment.connectionStore

        return VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "CONNECTIONS", tokens: tokens, icon: "bolt.horizontal")

            ForEach(store.connections) { connection in
                connectionRow(connection, tokens: tokens)
                if connection.kind == .claude {
                    SubscriptionAuthSection(
                        connection: connection, connectionStore: store,
                        oauthStore: environment.oauthStore, tokens: tokens)
                }
            }

            addConnectionRow(tokens: tokens)
        }
    }

    private func connectionRow(_ connection: Connection, tokens: DesignTokens) -> some View {
        let store = environment.connectionStore
        let isRevealed = revealedConnectionIDs.contains(connection.id)
        let requiresKey = ProviderPreset.preset(id: connection.presetID).requiresKey

        return HStack(spacing: 12) {
            Text(connection.displayName)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
                .frame(width: 110, alignment: .leading)

            if requiresKey {
                Text(isRevealed ? (store.token(for: connection) ?? "") : "••••••••••••")
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(connection.baseURL)
                    .font(AinkradFont.mono(12))
                    .foregroundStyle(tokens.foreground.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if requiresKey {
                    Button {
                        if isRevealed {
                            revealedConnectionIDs.remove(connection.id)
                        } else {
                            revealedConnectionIDs.insert(connection.id)
                        }
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }

                Button { testConnection(connection) } label: {
                    if testingIDs.contains(connection.id) {
                        AinkradSpinner(size: 14)
                    } else {
                        Image(systemName: "bolt.horizontal")
                            .font(.system(size: 12)).foregroundStyle(tokens.foreground.opacity(0.55))
                    }
                }
                .buttonStyle(.plain).help("Test connection")

                if let result = testResults[connection.id] {
                    Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(result.ok ? tokens.accentSecondary : tokens.accentTertiary)
                        .help(result.message)
                }

                Button {
                    revealedConnectionIDs.remove(connection.id)
                    store.removeConnection(connection)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(tokens.accentTertiary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .opacity(hoveredConnectionID == connection.id ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hoveredConnectionID)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
        .onHover { hovering in hoveredConnectionID = hovering ? connection.id : nil }
    }

    private func addConnectionRow(tokens: DesignTokens) -> some View {
        let preset = newPreset
        return VStack(alignment: .leading, spacing: 8) {
            // Keyed on the preset `id` (String) — `ProviderPreset` isn't Hashable
            // and lives out of task scope. The setter carries the exact
            // preset/baseURL/displayName write-back the old Menu did.
            AinkradSelect(
                items: ProviderPreset.all.map(\.id),
                selection: Binding(
                    get: { newPreset.id },
                    set: { id in
                        let p = ProviderPreset.preset(id: id)
                        newPreset = p
                        newBaseURL = p.defaultBaseURL
                        if newDisplayName.isEmpty { newDisplayName = p.displayName }
                        // Subscription auth only applies to Claude; reset when
                        // switching to any other preset so the key field returns.
                        if p.kind != .claude { newAuthMode = .apiKey }
                    }
                ),
                label: { ProviderPreset.preset(id: $0).displayName }
            )
            .fixedSize()

            // Claude can authenticate by API key OR by subscription (OAuth). The
            // subscription path creates a keyless connection here; the user then
            // signs in from the connection's row below.
            if preset.kind == .claude {
                AinkradSegmentedPicker(
                    items: [AuthMode.apiKey, .subscription],
                    selection: $newAuthMode,
                    label: { $0 == .apiKey ? "API key" : "Claude subscription" }
                )
            }

            if preset.allowsBaseURLEdit {
                NeonSecureField(text: $newBaseURL, placeholder: "Base URL", tokens: tokens)
            }
            HStack(spacing: 10) {
                if isNewSubscription {
                    Text("Add, then sign in below")
                        .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
                } else if preset.requiresKey {
                    NeonSecureField(text: $newConnectionToken, placeholder: "API key", tokens: tokens)
                } else {
                    Text("No API key required")
                        .font(AinkradFont.display(11)).foregroundStyle(tokens.foreground.opacity(0.45))
                }
                Button { addConnection() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canAddConnection ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
                }
                .buttonStyle(.plain).disabled(!canAddConnection)
            }
        }
        .padding(12)
        .background(ChamferShape(cut: AinkradRadius.sm).fill(tokens.surfaceElevated.opacity(0.45)))
    }

    private func testConnection(_ connection: Connection) {
        let svc = environment.modelCatalogService
        let oauthStore = environment.oauthStore
        testingIDs.insert(connection.id)
        Task {
            // Keyless subscription connections authenticate discovery/test with their
            // OAuth bearer, not an (empty) API key — mirrors the model picker's refresh.
            let credential: ProviderCredential
            if connection.authMode == .subscription {
                credential = (try? await oauthStore.liveCredential(for: connection)) ?? .apiKey("")
            } else {
                credential = .apiKey(environment.connectionStore.token(for: connection) ?? "")
            }
            let result = await svc.test(kind: connection.kind, baseURL: connection.baseURL, credential: credential)
            testResults[connection.id] = result
            testingIDs.remove(connection.id)
        }
    }

    /// The add-form is creating a keyless Claude subscription connection.
    private var isNewSubscription: Bool { newPreset.kind == .claude && newAuthMode == .subscription }

    private var canAddConnection: Bool {
        let hasKey = !newConnectionToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasURL = !newBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Subscription connections carry no key at creation — sign-in happens after.
        return (!newPreset.requiresKey || isNewSubscription || hasKey) && hasURL
    }

    private func addConnection() {
        guard canAddConnection else { return }
        let name = newDisplayName.isEmpty ? newPreset.displayName : newDisplayName
        let created = environment.connectionStore.addConnection(
            preset: newPreset, displayName: name, baseURL: newBaseURL,
            token: isNewSubscription ? "" : newConnectionToken,
            authMode: isNewSubscription ? .subscription : .apiKey)
        newConnectionToken = ""; newDisplayName = ""; newAuthMode = .apiKey
        modelPicker.refreshModels(for: created, environment)
    }
}
