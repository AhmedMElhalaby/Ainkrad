import SwiftUI

/// Attaches the M1 key map to the pane. A `ViewModifier` rather than scattered
/// `.onKeyPress` calls so the whole map is readable in one place — and so M2
/// can extend it without touching the views.
struct FilesKeyboardHandling: ViewModifier {
    let store: FilesPaneStore
    @Binding var isEditingPath: Bool

    private var tab: FilesTab { store.activeTab }

    /// While the path editor owns the keyboard, the unmodified navigation keys
    /// (arrows, Return, Delete, Space) belong to the TEXT FIELD — arrowing
    /// through a path you are typing must move the caret, not the file cursor.
    /// Command-modified bindings stay live throughout, since the field never
    /// wants those.
    private var navigationEnabled: Bool { !isEditingPath }

    func body(content: Content) -> some View {
        content
            .focusable()
            // Navigation — suppressed while the path editor is focused.
            .onKeyPress(.upArrow) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursor(by: -1)
                tab.selectCursor(extending: false)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursor(by: 1)
                tab.selectCursor(extending: false)
                return .handled
            }
            .onKeyPress(.return) {
                guard navigationEnabled else { return .ignored }
                tab.activateCursor()
                return .handled
            }
            .onKeyPress(.delete) {
                guard navigationEnabled else { return .ignored }
                tab.ascend()
                return .handled
            }
            .onKeyPress(.space) {
                guard navigationEnabled else { return .ignored }
                tab.selectCursor(extending: true)
                return .handled
            }
            // Selection
            .onKeyPress(keys: ["a"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.selectAll()
                return .handled
            }
            .onKeyPress(keys: ["i"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.invertSelection()
                return .handled
            }
            // View toggles
            .onKeyPress(keys: ["."], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.showHidden.toggle()
                store.persist()
                return .handled
            }
            // Path bar
            .onKeyPress(keys: ["l"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                isEditingPath = true
                return .handled
            }
            // Tabs
            .onKeyPress(keys: ["t"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                store.newTab()
                return .handled
            }
            .onKeyPress(keys: ["w"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                store.closeTab(at: store.activeTabIndex)
                return .handled
            }
            // History
            .onKeyPress(keys: ["["], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.goBack()
                return .handled
            }
            .onKeyPress(keys: ["]"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.goForward()
                return .handled
            }
    }
}

extension View {
    func filesKeyboardHandling(store: FilesPaneStore, isEditingPath: Binding<Bool>) -> some View {
        modifier(FilesKeyboardHandling(store: store, isEditingPath: isEditingPath))
    }
}
