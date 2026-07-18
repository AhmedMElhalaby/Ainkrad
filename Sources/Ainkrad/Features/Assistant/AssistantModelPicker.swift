import SwiftUI
import AinkradAppKit

/// Whether the composer's model pill should show the "Auto" badge — i.e. the
/// router is resolving the model each turn rather than a user pin winning
/// outright (mirrors `ModelRouter.route`'s own "pin wins over everything"
/// rule). Pure — unit tested without SwiftUI/AppEnvironment.
func modelPillShowsAutoBadge(pinnedModel: String?, routerEnabled: Bool) -> Bool {
    pinnedModel == nil && routerEnabled
}

/// Whether the composer model pill's SELECTION should sit on the "Auto" row
/// rather than a specific connection·model pair. Currently the exact same
/// rule as `modelPillShowsAutoBadge` — a separate name documents that this
/// drives the picker's selection sentinel, not just the badge glyph, so the
/// two can diverge later without silently breaking either call site.
func modelPillSelectionIsAuto(pinnedModel: String?, routerEnabled: Bool) -> Bool {
    modelPillShowsAutoBadge(pinnedModel: pinnedModel, routerEnabled: routerEnabled)
}

/// The model the pill DISPLAYS: an explicit pin always wins (matches
/// `ModelRouter.route`'s pin precedence); absent a pin, an enabled router
/// shows the model it last actually resolved to, falling back to the
/// standing default before any turn has settled; a disabled router with no
/// pin shows the standing default. Pure.
func modelPillDisplayModel(pinnedModel: String?, routerEnabled: Bool,
                            lastResolvedModel: String?, standingDefault: String) -> String {
    if let pinnedModel { return pinnedModel }
    if routerEnabled { return lastResolvedModel ?? standingDefault }
    return standingDefault
}

/// True when `model` is one of `curatedModels` (`ProviderPreset.curatedModels`
/// for the owning connection) — drives the verified/curated glyph in the
/// model picker's option rows. Pure.
func isCuratedModel(_ model: String, curatedModels: [String]) -> Bool {
    curatedModels.contains(model)
}

/// Option-row label for a (connection, model) pair: "Connection · Model",
/// prefixed with a verified/curated glyph when the model is one of the
/// connection's curated presets. Pure — the exact string
/// `AssistantConnectionModelPicker`'s row label renders.
func modelOptionRowLabel(connectionName: String, model: String, isCurated: Bool) -> String {
    let prefix = isCurated ? "✓ " : ""
    return "\(prefix)\(connectionName) · \(model)"
}

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
    /// pill, which lists a model under its owning connection). Also pins the
    /// model for the session (`RuntimeOptionsStore.pinModel`) — an explicit
    /// pick from the pill is an explicit pin, same as `/model <id>`.
    func selectConnectionModel(_ connection: Connection, model: String, _ environment: AppEnvironment) {
        let configStore = environment.agentConfigStore
        configStore.setActiveConnectionID(connection.id)
        configStore.setModel(model)
        environment.runtimeOptionsStore.pinModel(model)
    }

    /// Return the pill to "Auto": clears any explicit pin so the router picks
    /// the model each turn again — the pill-side counterpart to `/model auto`.
    func clearPin(_ environment: AppEnvironment) {
        environment.runtimeOptionsStore.pinModel(nil)
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
        // Piggyback a reachability refresh on the same user-triggered moment
        // (connection switch / picker open / manual refresh button) so the
        // Auto router's local-candidate gate (`AppEnvironment.candidatesProvider`)
        // reflects "is the local server up right now" without waiting for the
        // background 30s loop.
        Task {
            await environment.localModelAvailability.refresh(
                connections: store.connections, probe: environment.localModelProbe,
                tokenFor: { store.token(for: $0) })
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
        case auto
        case pair(connection: UUID, model: String)
        case manage
        case empty
    }

    private static let manageLabel = "Manage connections…"

    var body: some View {
        let connections = environment.connectionStore.connections
        let active = model.activeConnection(environment)

        var options: [Option] = [.auto]
        options += connections.flatMap { connection in
            model.modelOptions(for: connection).map { Option.pair(connection: connection.id, model: $0) }
        }
        options.append(.manage)

        return HStack(spacing: AinkradSpacing.xs) {
            AinkradSelect(
                items: options,
                selection: selectionBinding(active: active),
                label: label,
                searchPlaceholder: "Search connections & models…"
            )
            .fixedSize()
            .onAppear { if let c = active { model.refreshModels(for: c, environment) } }
            .onChange(of: active?.id) { _, _ in if let c = active { model.refreshModels(for: c, environment) } }

            routingBadge
        }
    }

    /// "AUTO" when the router is resolving the model each turn, "PINNED" when
    /// the user has pinned one — mirrors `AgentSwitcherView`'s neighboring
    /// pill in NOT using any native control, just a themed `AinkradBadge`.
    /// No badge at all when the router is disabled and nothing is pinned
    /// (today's plain default-model behavior, unchanged).
    @ViewBuilder
    private var routingBadge: some View {
        let pinned = environment.runtimeOptionsStore.options.pinnedModel
        let routerEnabled = environment.agentStore.active.routing.routerEnabled
        if modelPillShowsAutoBadge(pinnedModel: pinned, routerEnabled: routerEnabled) {
            AinkradBadge(text: "Auto", tint: tokens.accentSecondary)
        } else if pinned != nil {
            AinkradBadge(text: "Pinned", tint: tokens.accentPrimary)
        }
    }

    /// Maps the store's live selection to the matching pair (or `.empty`) for the
    /// getter, and routes the setter: a real pair → `selectConnectionModel`; the
    /// sentinel → `onManageConnections()` with NO model mutation (the computed
    /// getter re-reads the unchanged store, so the trigger label reverts on its
    /// own). The getter never crashes when the current model isn't yet in the
    /// discovered list — it still resolves a "Connection · Model" label.
    ///
    /// The displayed model is resolved via `modelPillDisplayModel`: a pin always
    /// wins; absent a pin, an enabled router shows the model it last actually
    /// resolved to (`AgentSession.lastUsageAttributedModel`) rather than the
    /// standing config default, so "Auto" reflects what really ran.
    private func selectionBinding(active: Connection?) -> Binding<Option> {
        Binding(
            get: {
                guard let active else { return .empty }
                let pinned = environment.runtimeOptionsStore.options.pinnedModel
                let routerEnabled = environment.agentStore.active.routing.routerEnabled
                if modelPillSelectionIsAuto(pinnedModel: pinned, routerEnabled: routerEnabled) {
                    return .auto
                }
                let displayModel = modelPillDisplayModel(
                    pinnedModel: pinned,
                    routerEnabled: routerEnabled,
                    lastResolvedModel: environment.agentSession.lastUsageAttributedModel,
                    standingDefault: environment.agentConfigStore.current.model)
                return .pair(connection: active.id, model: displayModel)
            },
            set: { option in
                switch option {
                case .auto:
                    model.clearPin(environment)
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
        case .auto:
            return "↺ Auto — router picks each turn"
        case .empty:
            return "No connection"
        case .manage:
            return AssistantConnectionModelPicker.manageLabel
        case .pair(let connectionID, let modelName):
            guard let connection = environment.connectionStore.connections.first(where: { $0.id == connectionID }) else {
                return "Connection · \(modelName)"
            }
            let curated = isCuratedModel(modelName, curatedModels: ProviderPreset.preset(id: connection.presetID).curatedModels)
            return modelOptionRowLabel(connectionName: connection.displayName, model: modelName, isCurated: curated)
        }
    }
}
