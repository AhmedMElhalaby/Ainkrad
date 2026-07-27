// Sources/Ainkrad/Core/AgentKit/Canvas/CanvasRenderTool.swift
import Foundation
import AinkradHostRuntime

/// The agent renders/updates visual output as canvas elements. This tool ONLY
/// draws UI from structured data — it executes nothing and touches no files or
/// system state, so it is not a new risk surface (spec §Security). Any tools the
/// agent runs to *produce* the content still pass the normal approval gate.
struct CanvasRenderTool: AgentTool {
    let store: CanvasStore

    let name = "canvas_render"
    let description = """
    Render or update the Live Canvas — a spatial surface of layered cards — instead of a wall of \
    chat text. Use it when output is structured or comparative (tables, diagrams, charts, code, \
    status boards, or several related cards). op: "add" a new element, "update" one in place \
    (stream a table/status as it fills), or "remove" it. kind: text | markdown | table | diagram \
    (mermaid source in body) | chart | image (url/data in body) | code | status | card. Prefer \
    normal chat for short conversational answers.
    """
    let permission: ToolPermissionClass = .read

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "op": .object([
                    "type": .string("string"),
                    "enum": .array([.string("add"), .string("update"), .string("remove")]),
                    "description": .string("Add a new element, update one in place, or remove it."),
                ]),
                "id": .object([
                    "type": .string("string"),
                    "description": .string("Stable element id. Required for update/remove."),
                ]),
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array(CanvasElementKind.allCases
                        .filter { $0 != .unknown }.map { .string($0.rawValue) }),
                    "description": .string("Element type (add/update)."),
                ]),
                "title": .object(["type": .string("string")]),
                "body": .object([
                    "type": .string("string"),
                    "description": .string("Content: markdown, mermaid source, CSV/markdown table, code, or image url/data."),
                ]),
                "language": .object(["type": .string("string"),
                                     "description": .string("Language for code elements.")]),
                "x": .object(["type": .string("number")]),
                "y": .object(["type": .string("number")]),
                "width": .object(["type": .string("number")]),
                "height": .object(["type": .string("number")]),
                "z": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("op")]),
        ])
    }

    @MainActor
    func execute(_ input: JSONValue) async throws -> ToolResult {
        let op = input["op"]?.stringValue ?? "add"
        switch op {
        case "remove":
            guard let id = input["id"]?.stringValue, !id.isEmpty else {
                throw ToolError.message("canvas_render remove requires \"id\".")
            }
            store.remove(id: id)
            return ToolResult(content: "Removed canvas element \(id).", isError: false)

        case "update":
            guard let id = input["id"]?.stringValue, !id.isEmpty else {
                throw ToolError.message("canvas_render update requires \"id\".")
            }
            var m = store.model
            CanvasReconstruction.apply(input, to: &m)          // create-or-merge, mirrors replay
            guard let updated = m.elements.first(where: { $0.id == id }) else {
                return ToolResult(content: "No canvas element \(id) to update.", isError: false)
            }
            // `store.upsert`, NOT `store.update(id:)`: the latter early-returns when
            // `id` isn't already in the LIVE store, silently dropping the write even
            // though `apply` just materialized it above — divergence from what
            // `CanvasReconstruction.rebuild` would produce for the same transcript.
            store.upsert(updated)
            return ToolResult(content: "Updated canvas element \(id).", isError: false)

        default: // add — unknown kinds are isolated to .unknown, never thrown
            guard let e = CanvasReconstruction.element(from: input, fallbackID: UUID().uuidString) else {
                throw ToolError.message("canvas_render add requires an element body/kind.")
            }
            let id = store.add(e)
            return ToolResult(content: "Rendered canvas element \(id) (\(e.kind.rawValue)).",
                              isError: false)
        }
    }

    func isIrreversible(_ input: JSONValue) -> Bool { false }
}
