import Foundation

/// The ordered steps of first-run setup.
///
/// `introducedIn` is the `setupVersion` that added the step. A user who completed
/// an earlier version is asked only for steps introduced since, rather than being
/// walked through the whole wizard again.
enum SetupStep: String, CaseIterable, Identifiable, Sendable {
    case welcome, home, appearance, motionAndSound, you, providers, assistant, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome:        return "Welcome"
        case .home:           return "Your Ainkrad Home"
        case .appearance:     return "Appearance"
        case .motionAndSound: return "Motion & Sound"
        case .you:            return "You"
        case .providers:      return "Connect an AI Provider"
        case .assistant:      return "Your Assistant"
        case .done:           return "Ready"
        }
    }

    /// The `setupVersion` this step was introduced in. Every case ships in
    /// version 1 today; a later release can add a step at version 2 and
    /// re-gate existing users on only that step.
    var introducedIn: Int { 1 }
}
