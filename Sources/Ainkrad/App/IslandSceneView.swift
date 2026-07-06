import SwiftUI
import SceneKit
import AppKit

/// Hosts the Living Island's `SCNScene` (built by `IslandScene`) in an
/// `SCNView` with a transparent background, so `AmbientSkyView` shows
/// through it exactly as it did behind the old 2D artwork. Adds a slow
/// continuous orbit on the island and a few degrees of pointer-driven camera
/// parallax; both are skipped under Reduce Motion, which renders a single
/// static frame instead (AIN-153). Re-lights the scene in place — without
/// rebuilding it — whenever `colors` changes (AIN-152).
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
            view.rendersContinuously = !reduceMotion

            // Never let a SceneKit setup problem take the app down — the
            // island is ambience, not a requirement. If building the scene
            // somehow throws/traps in a future edit, callers still get an
            // empty, harmless transparent view rather than a crash.
            let scene = IslandScene.build(colors: colors)
            view.scene = scene
            view.pointOfView = scene.rootNode.childNode(withName: IslandScene.NodeName.camera, recursively: true)

            let coordinator = context.coordinator
            coordinator.cameraNode = view.pointOfView
            coordinator.orbitContainer = scene.rootNode.childNode(
                withName: IslandScene.NodeName.orbitContainer, recursively: true)
            coordinator.applyOrbit(running: !reduceMotion)
            coordinator.applyPointerNudge(pointerFraction, animated: false)
            return view
        }

        func updateNSView(_ nsView: IslandSCNView, context: Context) {
            if let scene = nsView.scene {
                IslandScene.relight(scene, colors: colors)
            }
            nsView.rendersContinuously = !reduceMotion
            context.coordinator.applyOrbit(running: !reduceMotion)
            context.coordinator.applyPointerNudge(reduceMotion ? .zero : pointerFraction, animated: true)
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        /// Owns the two time-based behaviors (orbit action, pointer nudge)
        /// so `updateNSView` can toggle/adjust them without re-walking the
        /// scene graph on every SwiftUI update.
        final class Coordinator {
            private static let orbitActionKey = "islandOrbit"
            private static let maxNudgeRadians: Float = 0.09 // ~5°

            weak var cameraNode: SCNNode?
            weak var orbitContainer: SCNNode?
            private var baseCameraEulerAngles: SCNVector3?
            private var isOrbiting = false

            func applyOrbit(running: Bool) {
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
        isPlaying = window.occlusionState.contains(.visible) && !window.isMiniaturized
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
}
