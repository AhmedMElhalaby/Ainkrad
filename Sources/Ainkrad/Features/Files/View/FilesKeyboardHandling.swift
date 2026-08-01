import SwiftUI
import AppKit

/// Attaches the M1 key map to the pane. A `ViewModifier` rather than scattered
/// `.onKeyPress` calls so the whole map is readable in one place — and so M2
/// can extend it without touching the views.
struct FilesKeyboardHandling: ViewModifier {
    let store: FilesPaneStore
    let actions: FilesActions
    let undoStack: UndoStack
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onTogglePreview: () -> Void
    let onOpenFinder: (FilesFinderMode) -> Void
    let onFocusFilter: () -> Void
    /// True while a finder palette owns the keyboard.
    let isFinderOpen: Bool
    /// Opt-in modal navigation. Off by default — see `FilesSettingsStore`.
    let vimKeys: Bool
    @Binding var isEditingPath: Bool
    @FocusState private var keyboardFocus: Bool

    private var tab: FilesTab { store.activeTab }

    /// While the path editor owns the keyboard, the unmodified navigation keys
    /// (arrows, Return, Delete, Space) belong to the TEXT FIELD — arrowing
    /// through a path you are typing must move the caret, not the file cursor.
    /// Command-modified bindings stay live throughout, since the field never
    /// wants those.
    /// The path editor AND the finder palettes both take the keyboard: while
    /// either is up, unmodified keys belong to their text field.
    private var navigationEnabled: Bool { !isEditingPath && !isFinderOpen }

    /// Function keys are private-use unicode scalars, not `KeyEquivalent`
    /// members — `.f5` does not exist. These are the AppKit `NSF*FunctionKey`
    /// constants.
    private static let f2 = KeyEquivalent(Character(UnicodeScalar(0xF705)!))
    private static let f5 = KeyEquivalent(Character(UnicodeScalar(0xF708)!))
    private static let f6 = KeyEquivalent(Character(UnicodeScalar(0xF709)!))
    private static let f7 = KeyEquivalent(Character(UnicodeScalar(0xF70A)!))

    /// Shared by every arrow/page binding: guard, move, report handled.
    /// ⇧ extends the selection as it goes, which is the only case where
    /// cursor movement should touch `selection` at all.
    private func moveCursor(_ delta: Int) -> KeyPress.Result {
        guard navigationEnabled else { return .ignored }
        tab.moveCursor(by: delta)
        if NSEvent.modifierFlags.contains(.shift) {
            tab.selectCursor(extending: true)
        }
        return .handled
    }

    func body(content: Content) -> some View {
        content
            // Focused on appear, so the key map is live the moment the pane
            // opens. Without this the user had to click the list first, which
            // reads as "the keyboard doesn't work".
            .focusable()
            .focusEffectDisabled()
            .defaultFocus($keyboardFocus, true)
            .focused($keyboardFocus)
            // Navigation — suppressed while the path editor is focused.
            // Arrows move the CURSOR only. They used to rewrite `selection`
            // on every press, which invalidated every row's membership check
            // and re-rendered the whole list per keystroke. ⇧-arrow still
            // extends the selection, which is the case that wants it.
            .onKeyPress(.upArrow) { moveCursor(-1) }
            .onKeyPress(.downArrow) { moveCursor(1) }
            .onKeyPress(.pageUp) { moveCursor(-20) }
            .onKeyPress(.pageDown) { moveCursor(20) }
            .onKeyPress(.home) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursorToStart()
                return .handled
            }
            .onKeyPress(.end) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursorToEnd()
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
                tab.toggleCursorSelection()
                return .handled
            }
            // Clipboard — the ordinary idiom, and the primary one.
            .onKeyPress(keys: ["c"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                actions.copySelection()
                return .handled
            }
            .onKeyPress(keys: ["x"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                actions.cutSelection()
                return .handled
            }
            .onKeyPress(keys: ["v"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                Task { await actions.paste() }
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
            // Opt-in vim layer. Bound ONLY when enabled, so type-to-select
            // keeps working for everyone else.
            .onKeyPress(keys: ["h", "j", "k", "l", "g", "G"], phases: .down) { press in
                guard vimKeys, navigationEnabled, press.modifiers.isEmpty
                        || press.modifiers == [.shift] else { return .ignored }
                switch press.key.character {
                case "j": tab.moveCursor(by: 1)
                case "k": tab.moveCursor(by: -1)
                case "h": tab.ascend()
                case "l": tab.activateCursor()
                case "g": tab.moveCursorToStart()
                case "G": tab.moveCursorToEnd()
                default: return .ignored
                }
                return .handled
            }
            // Finder affordances. `/` filters here, ⌘F searches below here,
            // ⌘P jumps across the tree — three different questions, so three
            // different entry points rather than one overloaded box.
            // `/` is a second way into the same scoped field.
            .onKeyPress(keys: ["/"], phases: .down) { _ in
                guard navigationEnabled else { return .ignored }
                onFocusFilter()
                return .handled
            }
            // Plain ⌘F only. ⌘⇧F is handled by `FilesKeyMonitor`, because
            // `onKeyPress` proved unreliable for that chord — it depends on
            // this container holding focus, which it often does not.
            .onKeyPress(keys: ["f"], phases: .down) { press in
                guard press.modifiers.contains(.command),
                      !press.modifiers.contains(.shift) else { return .ignored }
                onOpenFinder(.globalSearch)
                return .handled
            }
            .onKeyPress(keys: ["p"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onOpenFinder(.jump)
                return .handled
            }
            // Preview strip — ⌘Y, matching Quick Look's muscle memory.
            .onKeyPress(keys: ["y"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onTogglePreview()
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
            // Operations — the orthodox function-key set. Guarded like the
            // navigation keys so they never fire while the path editor is up.
            .onKeyPress(keys: [Self.f5, Self.f6, Self.f2, Self.f7], phases: .down) { press in
                guard navigationEnabled else { return .ignored }
                switch press.key {
                case Self.f5: Task { await actions.copyToOtherPane() }
                case Self.f6: Task { await actions.moveToOtherPane() }
                case Self.f2: actions.beginRename()
                case Self.f7: actions.beginNewFolder()
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(keys: [.delete], phases: .down) { press in
                // ⌘⌫ trashes; bare Delete still ascends (handled above).
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                Task { await actions.trashSelection() }
                return .handled
            }
            // Undo / redo
            // Same uppercase problem as ⌘⇧F: ⌘⇧Z arrives as "Z", so binding
            // only "z" meant redo was unreachable from the keyboard.
            .onKeyPress(keys: ["z", "Z"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if press.modifiers.contains(.shift) || press.key.character == "Z" {
                    onRedo()
                } else {
                    onUndo()
                }
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
    func filesKeyboardHandling(store: FilesPaneStore, actions: FilesActions,
                               undoStack: UndoStack,
                               onUndo: @escaping () -> Void,
                               onRedo: @escaping () -> Void,
                               onTogglePreview: @escaping () -> Void,
                               onOpenFinder: @escaping (FilesFinderMode) -> Void,
                               onFocusFilter: @escaping () -> Void,
                               isFinderOpen: Bool,
                               vimKeys: Bool,
                               isEditingPath: Binding<Bool>) -> some View {
        modifier(FilesKeyboardHandling(store: store, actions: actions, undoStack: undoStack,
                                       onUndo: onUndo, onRedo: onRedo,
                                       onTogglePreview: onTogglePreview,
                                       onOpenFinder: onOpenFinder,
                                       onFocusFilter: onFocusFilter,
                                       isFinderOpen: isFinderOpen,
                                       vimKeys: vimKeys,
                                       isEditingPath: isEditingPath))
    }
}
