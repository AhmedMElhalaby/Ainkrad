// Sources/Ainkrad/Core/AgentKit/Tools/EditFileTool.swift
import Foundation

/// Find/replace file editor. `old_string` must match exactly once. Empty
/// `old_string` on a non-existent path creates the file. Any path is allowed;
/// the approval HUD (with the diff from `approvalPreview`) is the gate.
struct EditFileTool: AgentTool {
    let name = "edit_file"
    let description = """
    Replace an exact, unique substring of a file with new text. \
    `old_string` must appear exactly once. To create a new file, pass an empty \
    `old_string` and the full contents as `new_string`.
    """
    let permission: ToolPermissionClass = .write

    /// Optional undo substrate: when present, `execute` records before/after
    /// content for this edit. Nil-default keeps `EditFileTool()` byte-identical
    /// to pre-journal behavior.
    var journal: EditJournal? = nil

    var parametersSchema: JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"),
                                 "description": .string("Absolute path to the file to edit.")]),
                "old_string": .object(["type": .string("string"),
                                       "description": .string("Exact text to replace; must be unique. Empty to create a new file.")]),
                "new_string": .object(["type": .string("string"),
                                       "description": .string("Replacement text.")]),
            ]),
            "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
        ])
    }

    // Shared by execute (writes) and approvalPreview (renders) so the edit is
    // computed identically in both.
    private struct Edit { let path: String; let original: String; let updated: String }

    private func computeEdit(_ input: JSONValue) throws -> Edit {
        guard let path = input["path"]?.stringValue, !path.isEmpty else {
            throw ToolError.message("edit_file requires a non-empty \"path\".")
        }
        guard let oldString = input["old_string"]?.stringValue,
              let newString = input["new_string"]?.stringValue else {
            throw ToolError.message("edit_file requires \"old_string\" and \"new_string\".")
        }
        let exists = FileManager.default.fileExists(atPath: path)

        if oldString.isEmpty {
            if exists {
                throw ToolError.message("File already exists at \(path); pass a non-empty old_string to edit it.")
            }
            return Edit(path: path, original: "", updated: newString)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ToolError.message("No file exists at \(path).")
        }
        guard !isDirectory.boolValue else {
            throw ToolError.message("\(path) is a directory, not a file.")
        }
        let original: String
        do {
            original = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ToolError.message("Could not read \(path): \(error.localizedDescription).")
        }
        let occurrences = original.components(separatedBy: oldString).count - 1
        switch occurrences {
        case 0: throw ToolError.message("old_string was not found in \(path).")
        case 1: break
        default: throw ToolError.message("old_string appears \(occurrences) times in \(path); make it unique.")
        }
        let updated = original.replacingOccurrences(of: oldString, with: newString)
        return Edit(path: path, original: original, updated: updated)
    }

    func execute(_ input: JSONValue) async throws -> ToolResult {
        let edit = try computeEdit(input)
        let existedBefore = !(edit.original.isEmpty && (input["old_string"]?.stringValue ?? "").isEmpty)
        do {
            try edit.updated.write(toFile: edit.path, atomically: true, encoding: .utf8)
        } catch {
            throw ToolError.message("Could not write \(edit.path): \(error.localizedDescription).")
        }
        // Best-effort: journaling must never fail the edit it recorded.
        journal?.record(path: edit.path, before: edit.original, after: edit.updated, existedBefore: existedBefore)
        return ToolResult(content: "Edited \(edit.path).", isError: false)
    }

    func approvalPreview(_ input: JSONValue) -> ToolApprovalPreview {
        let path = input["path"]?.stringValue ?? "?"
        guard let edit = try? computeEdit(input) else {
            return ToolApprovalPreview(title: "Edit file", summary: path,
                                       diff: nil)
        }
        return ToolApprovalPreview(
            title: edit.original.isEmpty ? "Create file" : "Edit file",
            summary: path,
            diff: UnifiedDiff.make(old: edit.original, new: edit.updated, path: path))
    }
}

/// Minimal line-level unified diff for the approval card. Not a full LCS diff —
/// it brackets the changed region, which is sufficient for a find/replace edit.
enum UnifiedDiff {
    static func make(old: String, new: String, path: String) -> String {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")

        // Common prefix / suffix of unchanged lines.
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < (oldLines.count - prefix), suffix < (newLines.count - prefix),
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }

        var out = ["--- \(path)", "+++ \(path)"]
        let context = 2
        let ctxStart = max(0, prefix - context)
        for i in ctxStart..<prefix { out.append(" " + oldLines[i]) }
        for i in prefix..<(oldLines.count - suffix) { out.append("-" + oldLines[i]) }
        for i in prefix..<(newLines.count - suffix) { out.append("+" + newLines[i]) }
        let ctxEnd = min(oldLines.count, (oldLines.count - suffix) + context)
        for i in (oldLines.count - suffix)..<ctxEnd { out.append(" " + oldLines[i]) }
        return out.joined(separator: "\n")
    }
}
