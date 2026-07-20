import Foundation

/// Replays the transcript's `canvas_render` tool calls to rebuild a `CanvasModel`
/// from scratch. The canvas view itself never persists mutations directly — the
/// transcript is the source of truth, so closing and reopening a session never
/// loses data as long as the messages are retained.
enum CanvasReconstruction {
    static func rebuild(from messages: [AgentMessage], toolName: String = "canvas_render") -> CanvasModel {
        var model = CanvasModel()
        for message in messages {
            for block in message.content {
                guard case .toolUse(_, let name, let input) = block, name == toolName else { continue }
                apply(input, to: &model)
            }
        }
        return model
    }

    static func apply(_ input: JSONValue, to model: inout CanvasModel) {
        let op = input["op"]?.stringValue ?? "add"
        guard let id = input["id"]?.stringValue, !id.isEmpty else {
            // add without an id: synthesize one so replays stay deterministic-ish
            if op == "add", let e = element(from: input, fallbackID: UUID().uuidString) { model.upsert(e) }
            return
        }
        switch op {
        case "remove":
            model.remove(id: id)
        case "update":
            if var e = model.elements.first(where: { $0.id == id }) {
                merge(input, into: &e); model.upsert(e)
            } else if let e = element(from: input, fallbackID: id) {
                model.upsert(e)
            }
        default: // "add"
            if let e = element(from: input, fallbackID: id) {
                var withZ = e
                if withZ.z == 0 { withZ.z = model.nextZ }
                model.upsert(withZ)
            }
        }
    }

    /// Shared decode of an element from a tool-call input (reused by the
    /// `canvas_render` tool implementation). Synthesizes an id if the input
    /// omits one, so every decoded element has stable identity.
    static func element(from input: JSONValue) -> CanvasElement? {
        let fallbackID = input["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        return element(from: input, fallbackID: fallbackID)
    }

    static func element(from input: JSONValue, fallbackID: String) -> CanvasElement? {
        let kindRaw = input["kind"]?.stringValue ?? "card"
        let kind = CanvasElementKind(rawValue: kindRaw) ?? .unknown
        return CanvasElement(
            id: input["id"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackID,
            kind: kind,
            title: input["title"]?.stringValue,
            body: input["body"]?.stringValue ?? "",
            language: input["language"]?.stringValue,
            rect: rect(from: input),
            z: intValue(input["z"]) ?? 0)
    }

    private static func merge(_ input: JSONValue, into e: inout CanvasElement) {
        if let k = input["kind"]?.stringValue { e.kind = CanvasElementKind(rawValue: k) ?? .unknown }
        if let t = input["title"]?.stringValue { e.title = t }
        if let b = input["body"]?.stringValue { e.body = b }
        if let l = input["language"]?.stringValue { e.language = l }
        if let x = doubleValue(input["x"]) { e.rect.x = x }
        if let y = doubleValue(input["y"]) { e.rect.y = y }
        if let w = doubleValue(input["width"]) { e.rect.width = w }
        if let h = doubleValue(input["height"]) { e.rect.height = h }
    }

    private static func rect(from input: JSONValue) -> CanvasRect {
        var r = CanvasRect.defaultCard
        if let x = doubleValue(input["x"]) { r.x = x }
        if let y = doubleValue(input["y"]) { r.y = y }
        if let w = doubleValue(input["width"]) { r.width = w }
        if let h = doubleValue(input["height"]) { r.height = h }
        return r
    }

    private static func doubleValue(_ v: JSONValue?) -> Double? {
        guard let v else { return nil }
        if case .number(let n) = v { return n }
        if case .string(let s) = v { return Double(s) }
        return nil
    }
    private static func intValue(_ v: JSONValue?) -> Int? { doubleValue(v).map(Int.init) }
}
