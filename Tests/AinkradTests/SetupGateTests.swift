import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup gate")
@MainActor
struct SetupGateTests {
    // Plain text must reach the overlay. This is the bug that made four of the
    // wizard's eight steps unusable: every field was inert because the gate
    // consumed the keystroke before AppKit delivered it.
    @Test func plainCharactersReachTheOverlayWhileGated() {
        #expect(!SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                    isRegisteredShortcut: false, isWorkspaceChord: false,
                                    command: false, characters: "a", keyCode: 0))
    }

    @Test func editingChordsReachTheOverlayWhileGated() {
        for character in ["a", "c", "v", "x", "z"] {
            #expect(!SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                        isRegisteredShortcut: false, isWorkspaceChord: false,
                                        command: true, characters: character, keyCode: 0),
                    "⌘\(character.uppercased()) must reach a focused text field")
        }
    }

    @Test func registeredWorkspaceShortcutsAreSwallowedWhileGated() {
        #expect(SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                   isRegisteredShortcut: true, isWorkspaceChord: false,
                                   command: true, characters: "k", keyCode: 40))
    }

    @Test func hardcodedWorkspaceChordsAreSwallowedWhileGated() {
        #expect(SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                   isRegisteredShortcut: false, isWorkspaceChord: true,
                                   command: true, characters: "1", keyCode: 18))
    }

    // The trap that has now appeared four times at four depths.
    @Test func commandQAlwaysEscapes() {
        #expect(!SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                    isRegisteredShortcut: true, isWorkspaceChord: true,
                                    command: true, characters: "q", keyCode: 12))
    }

    // Dvorak puts "q" on keyCode 39, AZERTY on 0. Matching the physical key
    // strands those users with no keyboard escape.
    @Test func commandQEscapesOnNonQwertyLayouts() {
        for keyCode: UInt16 in [39, 0] {
            #expect(keyCode != 12)
            #expect(!SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: false,
                                        isRegisteredShortcut: false, isWorkspaceChord: false,
                                        command: true, characters: "q", keyCode: keyCode))
        }
    }

    @Test func quitConfirmationKeysPassOnlyWhileConfirming() {
        for keyCode: UInt16 in [36, 76, 53] {
            #expect(!SetupGate.swallows(isSetupPresented: true, isConfirmingQuit: true,
                                        isRegisteredShortcut: false, isWorkspaceChord: false,
                                        command: false, characters: nil, keyCode: keyCode))
        }
    }

    @Test func nothingIsSwallowedWhenTheGateIsDown() {
        #expect(!SetupGate.swallows(isSetupPresented: false, isConfirmingQuit: false,
                                    isRegisteredShortcut: true, isWorkspaceChord: true,
                                    command: true, characters: "k", keyCode: 40))
    }
}
