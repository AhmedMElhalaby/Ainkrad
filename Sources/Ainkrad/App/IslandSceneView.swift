import SwiftUI
import SceneKit
import AppKit

/// Hosts the Living Island's `SCNScene` (built by `IslandScene`) in an
/// `SCNView` with a transparent background, so `AmbientSkyView` shows
/// through it exactly as it did behind the old 2D artwork. Adds a slow
/// continuous orbit on the island and a few degrees of pointer-driven camera
/// parallax; under Reduce Motion the orbit and pointer parallax stop, the
/// ember/cloud particle systems stop emitting, and the render loop itself
/// is halted (`isPlaying = false`) so the island renders one fully static
/// frame (AIN-107/AIN-153). Re-lights the scene in place — without
/// rebuilding it, and only when `colors` actually changed — whenever
/// `updateNSView` runs (AIN-152).
///
/// `pointerFraction` is normalized to roughly -1...1 on each axis (0,0 =
/// center); the caller drives it from `.onContinuousHover`.
struct IslandSceneView: View {
    let colors: IslandPalette.LightColors
    let reduceMotion: Bool
    var pointerFraction: CGPoint = .zero

    var body: some View {
        Representable(colors: colors, reduceMotion: reduceMotion, pointerFraction: pointerFraction)
    }

    private struct Representable: NSViewRepresentable {
        let colors: IslandPalette.LightColors
        let reduceMotion: Bool
        let pointerFraction: CGPoint

        func makeNSView(context: Context) -> IslandSCNView {
            let view = IslandSCNView()
            view.backgroundColor = .clear
            view.antialiasingMode = .multisampling4X

            // Never let a SceneKit setup problem take the app down — the
            // island is ambience, not a requirement. If building the scene
            // somehow throws/traps in a future edit, callers still get an
            // empty, harmless transparent view rather than a crash.
            let scene = IslandScene.build(colors: colors, reduceMotion: reduceMotion)
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName: IslandScene.NodeName.camera, recursively: true)

            let coordinator = context.coordinator
            coordinator.cameraNode = view.pointOfView
            coordinator.orbitContainer = scene.rootNode.childNode(
                withName: IslandScene.NodeName.orbitContainer, recursively: true)
            coordinator.appliedColors = colors
            coordinator.applyReduceMotion(reduceMotion, to: view)
            coordinator.applyPointerNudge(pointerFraction, animated: false)
            return view
        }

        func updateNSView(_ nsView: IslandSCNView, context: Context) {
            context.coordinator.applyRelight(colors, to: nsView.scene)
            context.coordinator.applyReduceMotion(reduceMotion, to: nsView)
            context.coordinator.applyPointerNudge(reduceMotion ? .zero : pointerFraction, animated: true)
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        /// Owns the time-based behaviors (orbit action, particle emission,
        /// pointer nudge) plus the last-applied palette, so `updateNSView`
        /// can toggle/adjust them without re-walking the scene graph or
        /// re-lighting on every SwiftUI update (e.g. every hover-driven
        /// call) unless something actually changed.
        final class Coordinator {
            private static let orbitActionKey = "islandOrbit"
            private static let maxNudgeRadians: Float = 0.09 // ~5°

            weak var cameraNode: SCNNode?
            weak var orbitContainer: SCNNode?
            var appliedColors: IslandPalette.LightColors?
            private var baseCameraEulerAngles: SCNVector3?
            private var isOrbiting = false
            private var appliedReduceMotion: Bool?

            /// Re-lights the scene only when `colors` actually differ from
            /// the last-applied palette — `updateNSView` runs on every
            /// SwiftUI update, including every `.onContinuousHover` pointer
            /// move, and re-walking + re-coloring the scene graph on each of
            /// those is needless work (AIN-107 minor).
            func applyRelight(_ colors: IslandPalette.LightColors, to scene: SCNScene?) {
                guard let scene, appliedColors != colors else { return }
                appliedColors = colors
                IslandScene.relight(scene, colors: colors)
            }

            /// Makes the scene genuinely motionless under Reduce Motion:
            /// stops the orbit action, zeroes the ember/cloud particle
            /// birth rates, and halts the view's render loop outright
            /// (`isPlaying`, on top of `rendersContinuously`) — the render
            /// loop alone does not stop live particle emission. Restores
            /// all three when Reduce Motion turns back off, as long as the
            /// window is actually visible (occlusion gating still wins).
            func applyReduceMotion(_ reduceMotion: Bool, to view: IslandSCNView) {
                guard appliedReduceMotion != reduceMotion else { return }
                appliedReduceMotion = reduceMotion
                view.rendersContinuously = !reduceMotion
                view.reduceMotion = reduceMotion
                applyOrbit(running: !reduceMotion)
                if let scene = view.scene {
                    IslandScene.setParticlesActive(scene, active: !reduceMotion)
                }
            }

            private func applyOrbit(running: Bool) {
                guard let orbitContainer else { return }
                if running {
                    guard !isOrbiting else { return }
                    let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)
                    orbitContainer.runAction(.repeatForever(rotate), forKey: Self.orbitActionKey)
                    isOrbiting = true
                } else {
                    orbitContainer.removeAction(forKey: Self.orbitActionKey)
                    isOrbiting = false
                }
            }

            func applyPointerNudge(_ fraction: CGPoint, animated: Bool) {
                guard let cameraNode else { return }
                if baseCameraEulerAngles == nil {
                    baseCameraEulerAngles = cameraNode.eulerAngles
                }
                guard let base = baseCameraEulerAngles else { return }

                let clampedX: CGFloat = max(-1, min(1, fraction.x))
                let clampedY: CGFloat = max(-1, min(1, fraction.y))
                let maxNudge = CGFloat(Self.maxNudgeRadians)
                let nudgeX: CGFloat = CGFloat(base.x) - clampedY * maxNudge
                let nudgeY: CGFloat = CGFloat(base.y) + clampedX * maxNudge
                let nudged = SCNVector3(nudgeX, nudgeY, CGFloat(base.z))

                SCNTransaction.begin()
                SCNTransaction.animationDuration = animated ? 0.4 : 0
                cameraNode.eulerAngles = nudged
                SCNTransaction.commit()
            }
        }
    }
}

/// `SCNView` subclass that pauses the render/animation loop whenever its
/// window is occluded, miniaturized, or the view leaves its window — the
/// Living Island must cost ~zero GPU when it isn't actually visible
/// (AIN-153: "the island is ambience, never a cost").
final class IslandSCNView: SCNView {
    // `NSView.isOpaque` is get-only; a transparent SceneKit view overrides
    // it rather than assigning to it (the `.clear` `backgroundColor` above
    // is what actually makes it non-opaque for compositing).
    override var isOpaque: Bool { false }

    /// Mirrors `\.accessibilityReduceMotion`. Combined with window-occlusion
    /// state (below) to decide whether the render loop should actually run:
    /// either condition alone is enough to stop it, and resuming requires
    /// both Reduce Motion to be off *and* the window to be visible — so
    /// flipping Reduce Motion off while the window is occluded correctly
    /// stays paused, and the occlusion path is unaffected when Reduce
    /// Motion is off (AIN-107).
    var reduceMotion = false {
        didSet {
            guard reduceMotion != oldValue, let window else { return }
            updatePlaying(for: window)
        }
    }

    // `deinit` is nonisolated even on a @MainActor-inferred NSView subclass,
    // and `NSObjectProtocol` isn't `Sendable` — the token itself is just an
    // opaque handle that's safe to pass to `removeObserver` from anywhere.
    nonisolated(unsafe) private var occlusionObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let window else {
            isPlaying = false
            return
        }
        updatePlaying(for: window)
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window, queue: .main
        ) { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, let window else { return }
                self.updatePlaying(for: window)
            }
        }
    }

    private func updatePlaying(for window: NSWindow) {
        isPlaying = !reduceMotion && window.occlusionState.contains(.visible) && !window.isMiniaturized
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
}
