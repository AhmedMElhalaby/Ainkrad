import Foundation
import AVFoundation
import AinkradHostRuntime

/// Text-to-speech seam. `SystemSpeechSynthesizer` uses on-device AVFoundation
/// (no key, no network) — reusing the Voice subsystem rather than a provider.
protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String)
}

struct SystemSpeechSynthesizer: SpeechSynthesizing {
    // AVSpeechSynthesizer must outlive the call; hold one shared instance.
    // `AVSpeechSynthesizer` isn't Sendable, so the shared instance is pinned
    // to the main actor (matching `AgentTool`'s @MainActor isolation).
    @MainActor static let shared = AVSpeechSynthesizer()
    func speak(_ text: String) {
        MainActor.assumeIsolated {
            Self.shared.speak(AVSpeechUtterance(string: text))
        }
    }
}

struct SpeakTool: AgentTool {
    let synth: any SpeechSynthesizing

    let name = "speak"
    let description = "Speak text aloud on the user's machine using on-device text-to-speech."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "text": .object(["type": .string("string"),
                                 "description": .string("Text to speak aloud.")]),
            ]),
            "required": .array([.string("text")]),
        ])
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let text = input["text"]?.stringValue, !text.isEmpty else {
            throw ToolError.message("speak requires non-empty \"text\".")
        }
        synth.speak(text)
        return ToolResult(content: "Spoke \(text.count) characters.", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Speak", summary: input["text"]?.stringValue ?? "?", diff: nil)
    }
}
