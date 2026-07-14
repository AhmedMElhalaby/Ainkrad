import SwiftUI

/// The ONE home for the Assistant's connection+model selection logic, previously
/// duplicated in `AssistantRootView` and `AssistantSettingsView`. Consumers hold
/// it as `@State`; methods take the `AppEnvironment` so it stays decoupled.
@MainActor
@Observable
final class AssistantModelPickerModel {
    /// Live-discovered (or curated-fallback) model ids, keyed by connection id.
    var discoveredModels: [UUID: [String]] = [:]
    var isRefreshing = false

    /// The active connection: the configured one if it still exists, else the
    /// first connection.
    func activeConnection(_ environment: AppEnvironment) -> Connection? {
        let store = environment.connectionStore
        if let id = environment.agentConfigStore.activeConnectionID,
           let match = store.connections.first(where: { $0.id == id }) { return match }
        return store.connections.first
    }

    /// Models to offer for a connection: the discovered list if fetched, else
    /// the preset's curated fallback.
    func modelOptions(for connection: Connection?) -> [String] {
        guard let connection else { return [] }
        return discoveredModels[connection.id] ?? ProviderPreset.preset(id: connection.presetID).curatedModels
    }

    /// Switch the active connection AND reset its model to the curated default,
    /// then kick a live refresh.
    func selectConnection(_ connection: Connection, _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        configStore.setActiveConnectionID(connection.id)
        configStore.setModel(ProviderPreset.preset(id: connection.presetID).curatedModels.first ?? configStore.current.model)
        refreshModels(for: connection, environment)
    }

    /// Switch to a specific connection + model together (used by the grouped
    /// pill, which lists a model under its owning connection).
    func selectConnectionModel(_ connection: Connection, model: String, _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        configStore.setActiveConnectionID(connection.id)
        configStore.setModel(model)
    }

    func refreshModels(for connection: Connection, _ environment: AppEnvironment) {
        let store = environment.connectionStore
        let svc = environment.modelCatalogService
        let preset = ProviderPreset.preset(id: connection.presetID)
        let key = store.token(for: connection) ?? ""
        isRefreshing = true
        Task {
            let result = await svc.modelsResult(kind: connection.kind, baseURL: connection.baseURL,
                                                apiKey: key, curatedFallback: preset.curatedModels)
            discoveredModels[connection.id] = result.models
            isRefreshing = false
            if result.isLive {
                reconcileModelIfNeeded(for: connection, availableModels: result.models, environment)
            }
        }
    }

    /// If the active connection's model isn't valid for it (e.g. the Claude
    /// default on a fresh non-Claude connection), fall back to the first
    /// available model. Never overrides an explicitly chosen valid model. Only
    /// called on a genuinely live fetch — never on a curated fallback.
    private func reconcileModelIfNeeded(for connection: Connection, availableModels: [String], _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        guard activeConnection(environment)?.id == connection.id else { return }
        guard !availableModels.isEmpty, !availableModels.contains(configStore.current.model) else { return }
        configStore.setModel(availableModels[0])
    }
}

/// The composer's connection·model pill: a single menu grouped by connection,
/// each connection a submenu of its (discovered or curated) models. Selecting a
/// model switches connection + model together. A trailing "Manage connections…"
/// item opens Assistant settings. Seamless — no border, only a soft fill.
struct AssistantConnectionModelPicker: View {
    @Environment(AppEnvironment.self) private var environment
    let model: AssistantModelPickerModel
    let tokens: DesignTokens
    var onManageConnections: () -> Void

    var body: some View {
        let connections = environment.connectionStore.connections
        let active = model.activeConnection(environment)
        let currentModel = environment.agentConfigStore.current.model

        Menu {
            if connections.isEmpty {
                Text("No connections")
            } else {
                ForEach(connections) { connection in
                    Menu(connection.displayName) {
                        ForEach(model.modelOptions(for: connection), id: \.self) { m in
                            Button {
                                model.selectConnectionModel(connection, model: m, environment)
                            } label: {
                                if connection.id == active?.id && m == currentModel {
                                    Label(m, systemImage: "checkmark")
                                } else {
                                    Text(m)
                                }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Manage connections…") { onManageConnections() }
        } label: {
            HStack(spacing: 5) {
                Text(active?.displayName ?? "No connection")
                    .font(AinkradFont.display(11, weight: .medium))
                Text("·").foregroundStyle(tokens.foreground.opacity(0.35))
                Text(currentModel).font(AinkradFont.mono(11))
                Image(systemName: "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(tokens.foreground.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(tokens.surfaceElevated.opacity(0.45)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onAppear { if let c = active { model.refreshModels(for: c, environment) } }
        .onChange(of: active?.id) { _, _ in if let c = active { model.refreshModels(for: c, environment) } }
    }
}
