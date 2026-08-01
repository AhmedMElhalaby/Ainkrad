import Foundation
import AinkradAppKit
import AinkradAppKitContract

/// The MCP server Files publishes to the assistant.
///
/// **Division of labour.** AgentKit already ships `ReadFileTool`, `EditFileTool`,
/// `RunTerminalTool` and a Search family — so nothing here reads or edits file
/// CONTENT. Files owns what AgentKit has no tool for: navigation of the live
/// browser, and filesystem *manipulation*. Duplicating read/edit would be two
/// overlapping tools for one job and twice the surface to get wrong.
///
/// **Three invariants**, each load-bearing:
/// 1. Every mutation goes through `FileOperationEngine`, so an
///    assistant-initiated operation lands on the same `UndoStack` as a manual
///    one and is ⌘Z-able identically.
/// 2. Mutating tools are marked `destructive`, so the host's existing approval
///    gate shows the user what will happen before it runs.
/// 3. Every target is checked by `FilesToolScope`, so a misread instruction
///    fails closed instead of recursing from `/`.
@MainActor
enum FilesMCPServer {
    static func make(environment: AppEnvironment) -> MCPAppServer {
        let server = MCPAppServer(appID: FilesApp.id)
        addNavigationTools(to: server, environment: environment)
        addManipulationTools(to: server, environment: environment)
        addResources(to: server, environment: environment)
        return server
    }

    // MARK: - Helpers

    private static func arguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    private static func ok(_ text: String) -> AgentActionResult {
        AgentActionResult(text: text, isError: false)
    }

    private static func fail(_ text: String) -> AgentActionResult {
        AgentActionResult(text: text, isError: true)
    }

    /// Directories currently open in Files panes — the scope every inferred
    /// path is measured against.
    private static func openRoots(_ environment: AppEnvironment) -> [URL] {
        environment.filesPaneCoordinator.openDirectories
    }

    /// Resolves an argument to a URL and applies the scope rule in one place,
    /// so no tool can forget it.
    /// Not `Result`: its failure type must conform to `Error`, and
    /// `AgentActionResult` is a value the tool returns, not a thrown error.
    enum Resolution {
        case success(URL)
        case failure(AgentActionResult)
    }

    private static func resolve(_ path: String, environment: AppEnvironment) -> Resolution {
        let isAbsolute = path.hasPrefix("/") || path.hasPrefix("~")
        let expanded = expandTilde(path, home: environment.filesSystemService.homeDirectory)
        let url: URL
        if isAbsolute {
            url = URL(fileURLWithPath: expanded)
        } else if let first = openRoots(environment).first {
            url = first.appendingPathComponent(path)
        } else {
            return .failure(fail("No Files pane is open, so “\(path)” cannot be resolved. Pass an absolute path."))
        }

        switch FilesToolScope.decide(target: url, openRoots: openRoots(environment),
                                     wasExplicitlyAbsolute: isAbsolute) {
        case .allowed: return .success(url)
        case .refused(let reason): return .failure(fail(reason))
        }
    }

    // MARK: - Navigation (view control, no filesystem change)

    private static func addNavigationTools(to server: MCPAppServer, environment: AppEnvironment) {
        var navigate = MCPToolSpec(
            name: "files_navigate",
            description: "Point the Files browser at a directory.",
            schemaJSON: """
            {"type":"object","properties":{"path":{"type":"string","description":"Absolute path, or a path relative to the open pane."}},"required":["path"]}
            """,
            readOnly: true
        ) { json in
            guard let path = arguments(json)["path"] as? String else {
                return fail("Missing “path”.")
            }
            switch resolve(path, environment: environment) {
            case .failure(let error): return error
            case .success(let url):
                guard let pane = environment.filesPaneCoordinator.frontmostPane else {
                    return fail("No Files pane is open.")
                }
                let target = environment.filesSystemService.isDirectory(url)
                    ? url : url.deletingLastPathComponent()
                pane.activeTab.navigate(to: target)
                return ok("Navigated to \(target.path).")
            }
        }
        // Drives live view state, so the host must open the app first.
        navigate.requiresLiveApp = true
        server.addTool(navigate)

        server.addTool(MCPToolSpec(
            name: "files_get_selection",
            description: "The user's current selection in Files — the paths they are pointing at right now.",
            schemaJSON: #"{"type":"object","properties":{}}"#,
            readOnly: true
        ) { _ in
            guard let pane = environment.filesPaneCoordinator.frontmostPane else {
                return fail("No Files pane is open.")
            }
            let tab = pane.activeTab
            let selected = tab.selection.isEmpty
                ? tab.cursorEntry.map { [$0.url.path] } ?? []
                : tab.visibleEntries.filter { tab.selection.contains($0.url) }.map(\.url.path)
            guard !selected.isEmpty else { return ok("Nothing is selected in \(tab.currentDirectory.path).") }
            return ok(selected.joined(separator: "\n"))
        })

        var reveal = MCPToolSpec(
            name: "files_reveal",
            description: "Open the folder containing a path and select the item.",
            schemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}
            """,
            readOnly: true
        ) { json in
            guard let path = arguments(json)["path"] as? String else { return fail("Missing “path”.") }
            switch resolve(path, environment: environment) {
            case .failure(let error): return error
            case .success(let url):
                guard let pane = environment.filesPaneCoordinator.frontmostPane else {
                    return fail("No Files pane is open.")
                }
                pane.activeTab.navigate(to: url.deletingLastPathComponent())
                // Match by resolved path: assigning `selection = [url]`
                // directly silently selects nothing whenever the caller's URL
                // spells a symlinked prefix differently from the listing.
                guard pane.activeTab.select(matching: url) else {
                    return ok("Opened \(url.deletingLastPathComponent().path); “\(url.lastPathComponent)” is not in the listing.")
                }
                return ok("Revealed \(url.path).")
            }
        }
        reveal.requiresLiveApp = true
        server.addTool(reveal)
    }

    // MARK: - Manipulation

    private static func addManipulationTools(to server: MCPAppServer, environment: AppEnvironment) {
        let engine = environment.filesOperationEngine

        server.addTool(MCPToolSpec(
            name: "files_create_folder",
            description: "Create a new folder.",
            schemaJSON: """
            {"type":"object","properties":{"parent":{"type":"string"},"name":{"type":"string"}},"required":["parent","name"]}
            """,
            destructive: false
        ) { json in
            let args = arguments(json)
            guard let parent = args["parent"] as? String, let name = args["name"] as? String else {
                return fail("Missing “parent” or “name”.")
            }
            switch resolve(parent, environment: environment) {
            case .failure(let error): return error
            case .success(let url):
                let result = await engine.submit(FileOperation(
                    kind: .createFolder(name: name), sources: [], destinationDirectory: url))
                return summarise(result, success: "Created \(url.appendingPathComponent(name).path).")
            }
        })

        server.addTool(MCPToolSpec(
            name: "files_rename",
            description: "Rename a single file or folder in place.",
            schemaJSON: """
            {"type":"object","properties":{"path":{"type":"string"},"new_name":{"type":"string"}},"required":["path","new_name"]}
            """,
            destructive: true
        ) { json in
            let args = arguments(json)
            guard let path = args["path"] as? String, let newName = args["new_name"] as? String else {
                return fail("Missing “path” or “new_name”.")
            }
            switch resolve(path, environment: environment) {
            case .failure(let error): return error
            case .success(let url):
                let result = await engine.submit(FileOperation(
                    kind: .rename(newName: newName), sources: [url], destinationDirectory: nil))
                return summarise(result, success: "Renamed to \(newName).")
            }
        })

        addTransferTool(to: server, environment: environment, isMove: false)
        addTransferTool(to: server, environment: environment, isMove: true)

        server.addTool(MCPToolSpec(
            name: "files_trash",
            description: "Move paths to the Trash. Undoable — this never deletes permanently.",
            schemaJSON: """
            {"type":"object","properties":{"paths":{"type":"array","items":{"type":"string"}}},"required":["paths"]}
            """,
            destructive: true
        ) { json in
            guard let paths = arguments(json)["paths"] as? [String], !paths.isEmpty else {
                return fail("Missing “paths”.")
            }
            var urls: [URL] = []
            for path in paths {
                switch resolve(path, environment: environment) {
                case .failure(let error): return error   // fail the WHOLE call, not part of it
                case .success(let url): urls.append(url)
                }
            }
            let result = await engine.submit(FileOperation(
                kind: .trash, sources: urls, destinationDirectory: nil))
            return summarise(result, success: "Moved \(result.succeeded) item(s) to the Trash. Undo with ⌘Z.")
        })

        server.addTool(MCPToolSpec(
            name: "files_batch_rename",
            description: """
            Rename many files by replacing a substring in their names. \
            Undoable as ONE step. Highest-leverage and highest-blast-radius tool here.
            """,
            schemaJSON: """
            {"type":"object","properties":{"paths":{"type":"array","items":{"type":"string"}},"find":{"type":"string"},"replace":{"type":"string"}},"required":["paths","find","replace"]}
            """,
            destructive: true
        ) { json in
            let args = arguments(json)
            guard let paths = args["paths"] as? [String], !paths.isEmpty,
                  let find = args["find"] as? String, !find.isEmpty,
                  let replace = args["replace"] as? String else {
                return fail("Missing “paths”, “find” or “replace”.")
            }

            var renamed = 0
            var failures: [String] = []
            for path in paths {
                switch resolve(path, environment: environment) {
                case .failure(let error): return error
                case .success(let url):
                    let newName = url.lastPathComponent.replacingOccurrences(of: find, with: replace)
                    guard newName != url.lastPathComponent else { continue }
                    let result = await engine.submit(FileOperation(
                        kind: .rename(newName: newName), sources: [url], destinationDirectory: nil))
                    if result.failures.isEmpty { renamed += 1 }
                    else { failures.append("\(url.lastPathComponent): \(result.failures[0].reason)") }
                }
            }
            if renamed == 0 && failures.isEmpty { return ok("No names matched “\(find)”.") }
            var text = "Renamed \(renamed) item(s)."
            if !failures.isEmpty { text += " Failed: \(failures.joined(separator: "; "))" }
            return AgentActionResult(text: text, isError: !failures.isEmpty)
        })
    }

    private static func addTransferTool(to server: MCPAppServer, environment: AppEnvironment,
                                        isMove: Bool) {
        let engine = environment.filesOperationEngine
        let verb = isMove ? "move" : "copy"
        server.addTool(MCPToolSpec(
            name: "files_\(verb)",
            description: "\(verb.capitalized) paths into a destination directory. Undoable.",
            schemaJSON: """
            {"type":"object","properties":{"paths":{"type":"array","items":{"type":"string"}},"destination":{"type":"string"},"on_conflict":{"type":"string","enum":["replace","keep_both","skip"]}},"required":["paths","destination"]}
            """,
            destructive: isMove
        ) { json in
            let args = arguments(json)
            guard let paths = args["paths"] as? [String], !paths.isEmpty,
                  let destination = args["destination"] as? String else {
                return fail("Missing “paths” or “destination”.")
            }
            var urls: [URL] = []
            for path in paths {
                switch resolve(path, environment: environment) {
                case .failure(let error): return error
                case .success(let url): urls.append(url)
                }
            }
            guard case .success(let destinationURL) = resolve(destination, environment: environment) else {
                return fail("Destination “\(destination)” is not reachable.")
            }
            // Default to keep-both, never replace: an unattended overwrite is
            // the one outcome the user cannot see coming.
            let policy: ConflictPolicy
            switch args["on_conflict"] as? String {
            case "replace": policy = .replace
            case "skip": policy = .skip
            default: policy = .keepBoth
            }
            let result = await engine.submit(FileOperation(
                kind: isMove ? .move : .copy, sources: urls,
                destinationDirectory: destinationURL, policy: policy))
            return summarise(result, success: "\(verb.capitalized)d \(result.succeeded) item(s) to \(destinationURL.path).")
        })
    }

    private static func summarise(_ result: OperationResult, success: String) -> AgentActionResult {
        guard result.failures.isEmpty else {
            let detail = result.failures.map { "\($0.url.lastPathComponent): \($0.reason)" }
                .joined(separator: "; ")
            return fail("Partially failed — \(result.succeeded) succeeded, \(result.failures.count) failed. \(detail)")
        }
        return ok(success)
    }

    // MARK: - Resources

    private static func addResources(to server: MCPAppServer, environment: AppEnvironment) {
        server.addResource(MCPResourceSpec(
            uri: "files://current-directory",
            title: "Files — current directory listing"
        ) {
            guard let pane = environment.filesPaneCoordinator.frontmostPane else {
                return "No Files pane is open."
            }
            let tab = pane.activeTab
            let listing = tab.visibleEntries
                .map { "\($0.isDirectory ? "d" : "-") \($0.name)" }
                .joined(separator: "\n")
            return "\(tab.currentDirectory.path)\n\(listing)"
        })
    }
}
