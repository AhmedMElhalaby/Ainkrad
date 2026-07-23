import Foundation

// `Result`'s `Failure` generic parameter requires `Error` conformance.
// The brief's interface calls for a plain `String` usage message as the
// failure value, so this narrow, additive conformance lets `String` be used
// directly as that message without introducing a bespoke error type.
extension String: @retroactive Error {}

/// Parsed launch arguments for `AinkradDevHost` — the dev-only host that
/// loads a single plugin bundle (specified via `--bundle`) for local
/// development, optionally pinned to a `--generation` for reload testing.
struct LaunchArguments {
    let bundleURL: URL
    let generation: Int?

    private static let usage = "usage: AinkradDevHost --bundle <path> [--generation N]"

    static func parse(_ arguments: [String]) -> Result<LaunchArguments, String> {
        var bundlePath: String?
        var generationValue: Int?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--bundle":
                guard index + 1 < arguments.count else { return .failure(usage) }
                bundlePath = arguments[index + 1]
                index += 2
            case "--generation":
                guard index + 1 < arguments.count else { return .failure(usage) }
                guard let generation = Int(arguments[index + 1]) else { return .failure(usage) }
                generationValue = generation
                index += 2
            default:
                index += 1
            }
        }

        guard let bundlePath else { return .failure(usage) }
        return .success(LaunchArguments(bundleURL: URL(fileURLWithPath: bundlePath), generation: generationValue))
    }
}
