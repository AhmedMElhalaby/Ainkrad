import SceneKit
import AppKit
import Foundation

/// Builds the procedural geometry for the Living Island (AIN-107/AIN-150): a
/// stylized low-poly floating island — central spire/citadel, an arch ring,
/// an inverted-cone base, a few satellite islets, and ember + cloud
/// atmosphere. No external asset: every primitive is generated in code here,
/// isolated behind `IslandScene.build(colors:)` so a USDZ scene could later
/// slot into the same seam without `IslandSceneView` changing at all.
///
/// `IslandSceneView` owns *time* (the orbit action, pointer parallax,
/// Reduce-Motion/occlusion gating) — this type only owns the static scene
/// graph and its resting-state camera, plus re-lighting an existing graph in
/// place when the theme changes.
enum IslandScene {
    /// Node names used to find specific nodes again later (re-lighting,
    /// hosting the camera) without keeping scene-graph references around.
    enum NodeName {
        static let orbitContainer = "island.orbitContainer"
        static let camera = "island.camera"
        static let spireWindowLight = "island.spireWindowLight"
        static let ringLight = "island.ringLight"
        static let ring = "island.ring"
        static let emberParticles = "island.emberParticles"
    }

    /// Builds a fresh scene, already lit for `colors`. The root's background
    /// is left transparent (`contents = nil`) — `IslandSceneView` also clears
    /// the hosting `SCNView`'s background so the ambient sky behind it shows
    /// through both layers.
    static func build(colors: IslandPalette.LightColors) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = nil

        let orbit = SCNNode()
        orbit.name = NodeName.orbitContainer
        scene.rootNode.addChildNode(orbit)

        orbit.addChildNode(makeBase())
        orbit.addChildNode(makeSpire(colors: colors))
        orbit.addChildNode(makeRing(colors: colors))
        makeSatelliteIslets().forEach { orbit.addChildNode($0) }
        orbit.addChildNode(makeEmberParticles(colors: colors))
        orbit.addChildNode(makeCloudDrift())

        scene.rootNode.addChildNode(makeAmbientLight())
        scene.rootNode.addChildNode(makeCamera())

        return scene
    }

    /// Re-lights an already-built scene in place for a new theme — walks the
    /// graph by node name and swaps light/emissive colors, without touching
    /// geometry. Cheap enough to call on every theme change.
    static func relight(_ scene: SCNScene, colors: IslandPalette.LightColors) {
        let primary = NSColor(colors.primary)
        let secondary = NSColor(colors.secondary)

        scene.rootNode.enumerateHierarchy { node, _ in
            switch node.name {
            case NodeName.spireWindowLight:
                node.light?.color = primary
            case NodeName.ringLight:
                node.light?.color = secondary
            case NodeName.ring:
                node.geometry?.firstMaterial?.emission.contents = secondary
            case NodeName.emberParticles:
                node.particleSystems?.forEach { $0.particleColor = secondary }
            default:
                if node.geometry?.name == "spireWindow" {
                    node.geometry?.firstMaterial?.emission.contents = primary
                }
            }
        }
    }

    // MARK: - Geometry

    /// The inverted-cone base beneath the citadel — wide at the top (where it
    /// meets the spire), narrowing to a point below, the classic "floating
    /// island" silhouette.
    private static func makeBase() -> SCNNode {
        let cone = SCNCone(topRadius: 1.7, bottomRadius: 0.1, height: 1.3)
        cone.radialSegmentCount = 10
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = NSColor(calibratedWhite: 0.16, alpha: 1)
        cone.firstMaterial = material

        let node = SCNNode(geometry: cone)
        node.position = SCNVector3(0, -0.6, 0)
        return node
    }

    /// The central spire/citadel: a stacked cylinder base, a boxy mid-tower
    /// with a few emissive "windows", and a tapering cone tip.
    private static func makeSpire(colors: IslandPalette.LightColors) -> SCNNode {
        let group = SCNNode()

        let stoneMaterial = SCNMaterial()
        stoneMaterial.lightingModel = .lambert
        stoneMaterial.diffuse.contents = NSColor(calibratedWhite: 0.22, alpha: 1)

        let base = SCNCylinder(radius: 0.5, height: 0.7)
        base.radialSegmentCount = 8
        base.firstMaterial = stoneMaterial
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, 0.35, 0)
        group.addChildNode(baseNode)

        let tower = SCNBox(width: 0.46, height: 0.9, length: 0.46, chamferRadius: 0.04)
        tower.firstMaterial = stoneMaterial
        let towerNode = SCNNode(geometry: tower)
        towerNode.position = SCNVector3(0, 1.15, 0)
        group.addChildNode(towerNode)

        let tip = SCNCone(topRadius: 0, bottomRadius: 0.32, height: 1.0)
        tip.radialSegmentCount = 8
        tip.firstMaterial = stoneMaterial
        let tipNode = SCNNode(geometry: tip)
        tipNode.position = SCNVector3(0, 2.1, 0)
        group.addChildNode(tipNode)

        // Windows: small emissive planes on two faces of the tower, each
        // paired with a point light so the glow bleeds onto nearby geometry.
        for angle: Float in [0, .pi / 2, .pi, 3 * .pi / 2] {
            let window = SCNPlane(width: 0.12, height: 0.18)
            window.name = "spireWindow"
            let windowMaterial = SCNMaterial()
            windowMaterial.lightingModel = .constant
            windowMaterial.diffuse.contents = NSColor(colors.primary)
            windowMaterial.emission.contents = NSColor(colors.primary)
            window.firstMaterial = windowMaterial

            let windowNode = SCNNode(geometry: window)
            let radius: Float = 0.235
            windowNode.position = SCNVector3(sin(angle) * radius, 1.15, cos(angle) * radius)
            windowNode.eulerAngles = SCNVector3(0, angle, 0)
            group.addChildNode(windowNode)
        }

        let windowLight = SCNLight()
        windowLight.type = .omni
        windowLight.color = NSColor(colors.primary)
        windowLight.intensity = 90
        windowLight.attenuationEndDistance = 3
        let windowLightNode = SCNNode()
        windowLightNode.name = NodeName.spireWindowLight
        windowLightNode.light = windowLight
        windowLightNode.position = SCNVector3(0, 1.15, 0)
        group.addChildNode(windowLightNode)

        return group
    }

    /// The arch ring around the spire — an `SCNTorus` with a theme-tinted
    /// emissive material, plus a soft point light so it casts a colored glow.
    private static func makeRing(colors: IslandPalette.LightColors) -> SCNNode {
        let torus = SCNTorus(ringRadius: 1.15, pipeRadius: 0.05)
        torus.ringSegmentCount = 24
        torus.pipeSegmentCount = 8

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor(calibratedWhite: 0.3, alpha: 1)
        material.emission.contents = NSColor(colors.secondary)
        torus.firstMaterial = material

        let node = SCNNode(geometry: torus)
        node.name = NodeName.ring
        node.position = SCNVector3(0, 0.95, 0)
        node.eulerAngles = SCNVector3(Float.pi / 2.2, 0, 0)

        let light = SCNLight()
        light.type = .omni
        light.color = NSColor(colors.secondary)
        light.intensity = 60
        light.attenuationEndDistance = 3
        let lightNode = SCNNode()
        lightNode.name = NodeName.ringLight
        lightNode.light = light
        lightNode.position = SCNVector3(0, 0.95, 0)
        node.addChildNode(lightNode)

        return node
    }

    /// A handful of small rock/sphere islets orbiting the citadel at
    /// different heights and distances — kept low-poly and unlit beyond
    /// ambient, they're background detail, not a focal point.
    private static func makeSatelliteIslets() -> [SCNNode] {
        let offsets: [(x: Float, y: Float, z: Float, radius: Float)] = [
            (1.9, -0.15, 0.6, 0.16),
            (-1.7, 0.35, -0.8, 0.13),
            (0.5, -0.5, -1.9, 0.11),
            (-1.1, 0.6, 1.6, 0.09),
        ]
        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = NSColor(calibratedWhite: 0.2, alpha: 1)

        return offsets.map { offset in
            let sphere = SCNSphere(radius: CGFloat(offset.radius))
            sphere.segmentCount = 8
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(offset.x, offset.y, offset.z)
            return node
        }
    }

    // MARK: - Atmosphere

    /// Rising ember sparks — modest budget (a few dozen live particles),
    /// additive blending, tinted by the theme's secondary color.
    private static func makeEmberParticles(colors: IslandPalette.LightColors) -> SCNNode {
        let system = SCNParticleSystem()
        system.birthRate = 8
        system.particleLifeSpan = 3.2
        system.particleLifeSpanVariation = 1.0
        system.particleSize = 0.045
        system.particleSizeVariation = 0.02
        system.particleVelocity = 0.35
        system.particleVelocityVariation = 0.15
        system.spreadingAngle = 28
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.acceleration = SCNVector3(0, 0.18, 0)
        system.particleColor = NSColor(colors.secondary)
        system.blendMode = .additive
        system.particleImage = softDotImage()
        system.emitterShape = SCNCone(topRadius: 0, bottomRadius: 1.4, height: 0.1)
        system.isAffectedByGravity = false
        system.loops = true

        let node = SCNNode()
        node.name = NodeName.emberParticles
        node.position = SCNVector3(0, -0.6, 0)
        node.addParticleSystem(system)
        return node
    }

    /// A few slow, soft cloud puffs drifting beneath the island — very low
    /// birth rate and long life, so it reads as ambient haze, not "snow".
    private static func makeCloudDrift() -> SCNNode {
        let system = SCNParticleSystem()
        system.birthRate = 1.2
        system.particleLifeSpan = 14
        system.particleLifeSpanVariation = 4
        system.particleSize = 1.1
        system.particleSizeVariation = 0.4
        system.particleVelocity = 0.06
        system.particleVelocityVariation = 0.03
        system.spreadingAngle = 180
        system.particleColor = NSColor(calibratedWhite: 1, alpha: 0.08)
        system.blendMode = .alpha
        system.particleImage = softDotImage()
        system.emitterShape = SCNSphere(radius: 1.6)
        system.isAffectedByGravity = false
        system.loops = true

        let node = SCNNode()
        node.position = SCNVector3(0, -1.4, 0)
        node.addParticleSystem(system)
        return node
    }

    // MARK: - Lights & camera

    /// Neutral ambient fill so the island's silhouette reads regardless of
    /// theme — the theme's *color* comes from the point lights + emissive
    /// materials above, not from this.
    private static func makeAmbientLight() -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.color = NSColor(calibratedWhite: 0.45, alpha: 1)
        let node = SCNNode()
        node.light = light
        return node
    }

    /// A fixed resting-state camera looking at the island from slightly
    /// above eye level. `IslandSceneView` nudges this node's rotation a few
    /// degrees for pointer parallax; it does not move with the orbiting
    /// geometry (the orbit spins the island, not the camera).
    private static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 0.1
        camera.zFar = 20

        let node = SCNNode()
        node.name = NodeName.camera
        node.camera = camera
        node.position = SCNVector3(0, 0.6, 5.4)
        node.look(at: SCNVector3(0, 0.6, 0))
        return node
    }

    /// A small procedurally-drawn soft-edged dot, used as the particle
    /// sprite for both embers and clouds — no bundled image asset needed.
    /// Generated once and reused (particle systems copy `contents`, not the
    /// live `NSImage`, so a shared static instance is safe).
    private static let softDotImageCache: NSImage = {
        let diameter: CGFloat = 24
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            let colors = [
                NSColor.white.withAlphaComponent(0.9).cgColor,
                NSColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: diameter / 2, y: diameter / 2), startRadius: 0,
                    endCenter: CGPoint(x: diameter / 2, y: diameter / 2), endRadius: diameter / 2,
                    options: []
                )
            }
        }
        image.unlockFocus()
        return image
    }()

    private static func softDotImage() -> NSImage { softDotImageCache }
}
