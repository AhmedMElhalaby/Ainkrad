import Foundation
import AinkradHostRuntime

/// Generates an image from a prompt and renders it as an `image` card on the
/// Live Canvas (body = a data: URL), exactly like `canvas_render`'s image kind.
/// Read-class + reversible: it draws a card and touches no files/system state
/// (the paid network call is the only side effect; the approval gate is the
/// backstop when reads are gated).
struct ImageGenerateTool: AgentTool {
    let backend: any MediaBackend
    let store: CanvasStore

    let name = "image_generate"
    let description = "Generate an image from a text prompt and render it as an image card on the Live Canvas."
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "prompt": .object(["type": .string("string"),
                                   "description": .string("Text description of the image to generate.")]),
                "title": .object(["type": .string("string"),
                                  "description": .string("Optional card title.")]),
            ]),
            "required": .array([.string("prompt")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        guard let prompt = input["prompt"]?.stringValue, !prompt.isEmpty else {
            throw ToolError.message("image_generate requires a non-empty \"prompt\".")
        }
        guard backend.isConfigured else {
            return ToolResult(
                content: "Image generation is not configured. Add a media API key in Settings → Assistant → Media.",
                isError: false)
        }
        let image = try await backend.generateImage(prompt: prompt)
        let dataURL = "data:\(image.mediaType);base64,\(image.base64)"
        let element = CanvasElement(
            id: UUID().uuidString, kind: .image,
            title: input["title"]?.stringValue ?? prompt, body: dataURL)
        let id = store.add(element)
        return ToolResult(content: "Rendered generated image as canvas element \(id).", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        ToolApprovalPreview(title: "Generate image", summary: input["prompt"]?.stringValue ?? "?", diff: nil)
    }

    func isIrreversible(_ input: JSONValue) -> Bool { false }
}
