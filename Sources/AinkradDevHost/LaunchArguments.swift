import Foundation

/// Failure case for `LaunchArguments.parse` — a dedicated error type instead
/// of a bare `String`, so this module doesn't need a project-wide
/// `String: Error` conformance just to satisfy `Result`'s `Failure`
/// requirement.
enum LaunchArgumentsError: Error, CustomStringConvertible, Equatable {
    case usage(String)

    var description: String {
        switch self {
        case .usage(let message):
            return message
        }
    }
}

/// Parsed launch arguments for `AinkradDevHost` — the dev-only host that
/// loads a single plugin bundle (specified via `--bundle`) for local
/// development, optionally pinned to a `--generation` for reload testing.
struct LaunchArguments {
    let bundleURL: URL
    let generation: Int?

    private static let usage = "usage: AinkradDevHost --bundle <path> [--generation N]"

    static func parse(_ arguments: [String]) -> Result<LaunchArguments, LaunchArgumentsError> {
        var bundlePath: String?
        var generationValue: Int?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--bundle":
                guard index + 1 < arguments.count else { return .failure(.usage(usage)) }
                bundlePath = arguments[index + 1]
                index += 2
            case "--generation":
                guard index + 1 < arguments.count else { return .failure(.usage(usage)) }
                guard let generation = Int(arguments[index + 1]) else { return .failure(.usage(usage)) }
                generationValue = generation
                index += 2
            default:
                index += 1
            }
        }

        guard let bundlePath else { return .failure(.usage(usage)) }
        return .success(LaunchArguments(bundleURL: URL(fileURLWithPath: bundlePath), generation: generationValue))
    }
}
