import SwiftUI
import AinkradAppKit

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

/// The composer's connection·model picker: ONE searchable select (never a
/// nested `Menu`) whose options are `(connection, model)` pairs rendered
/// "Connection · Model", plus a trailing "Manage connections…" sentinel.
/// Selecting a pair switches connection + model together; the sentinel opens
/// Assistant settings WITHOUT mutating the selection. Seamless — the kit
/// control carries its own chamfer chrome.
struct AssistantConnectionModelPicker: View {
    @Environment(AppEnvironment.self) private var environment
    let model: AssistantModelPickerModel
    let tokens: DesignTokens
    var onManageConnections: () -> Void

    /// The flattened option space: a real connection+model pair, the "Manage
    /// connections…" sentinel, or an empty placeholder when no connection exists.
    private enum Option: Hashable {
        case pair(connection: UUID, model: String)
        case manage
        case empty
    }

    private static let manageLabel = "Manage connections…"

    var body: some View {
        let connections = environment.connectionStore.connections
        let active = model.activeConnection(environment)

        var options: [Option] = connections.flatMap { connection in
            model.modelOptions(for: connection).map { Option.pair(connection: connection.id, model: $0) }
        }
        options.append(.manage)

        return AinkradSearchableSelect(
            items: options,
            selection: selectionBinding(active: active),
            label: label,
            placeholder: "Search connections & models…"
        )
        .fixedSize()
        .onAppear { if let c = active { model.refreshModels(for: c, environment) } }
        .onChange(of: active?.id) { _, _ in if let c = active { model.refreshModels(for: c, environment) } }
    }

    /// Maps the store's live selection to the matching pair (or `.empty`) for the
    /// getter, and routes the setter: a real pair → `selectConnectionModel`; the
    /// sentinel → `onManageConnections()` with NO model mutation (the computed
    /// getter re-reads the unchanged store, so the trigger label reverts on its
    /// own). The getter never crashes when the current model isn't yet in the
    /// discovered list — it still resolves a "Connection · Model" label.
    private func selectionBinding(active: Connection?) -> Binding<Option> {
        Binding(
            get: {
                guard let active else { return .empty }
                return .pair(connection: active.id, model: environment.agentConfigStore.current.model)
            },
            set: { option in
                switch option {
                case .pair(let connectionID, let modelName):
                    if let connection = environment.connectionStore.connections.first(where: { $0.id == connectionID }) {
                        model.selectConnectionModel(connection, model: modelName, environment)
                    }
                case .manage:
                    onManageConnections()
                case .empty:
                    break
                }
            }
        )
    }

    private func label(_ option: Option) -> String {
        switch option {
        case .empty:
            return "No connection"
        case .manage:
            return AssistantConnectionModelPicker.manageLabel
        case .pair(let connectionID, let modelName):
            let name = environment.connectionStore.connections
                .first(where: { $0.id == connectionID })?.displayName ?? "Connection"
            return "\(name) · \(modelName)"
        }
    }
}
