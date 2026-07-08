#!/usr/bin/env swift
//
// gen-island-depth.swift
//
// Generates grayscale depth-map PNGs for the "Living Island" hero artwork
// used by the empty-workspace home screen's 2.5D depth parallax shader.
//
// White = NEAR (bright citadel), Black = FAR (dark sky / edges).
//
// Usage:
//   swift scripts/gen-island-depth.swift [--preview]
//
// --preview also writes a side-by-side "art | depth" composite PNG per
// source image into the scratchpad directory below, for eyeballing.

import AppKit
import CoreImage
import Foundation

// MARK: - Config

struct IslandSource {
    let name: String
    let sourceImageset: String
    let depthImageset: String
}

let sources: [IslandSource] = [
    IslandSource(
        name: "NeonBlue",
        sourceImageset: "Island-NeonBlue.imageset/Island-NeonBlue.png",
        depthImageset: "Island-NeonBlue-Depth.imageset/Island-NeonBlue-Depth.png"
    ),
    IslandSource(
        name: "CyberPurple",
        sourceImageset: "Island-CyberPurple.imageset/Island-CyberPurple.png",
        depthImageset: "Island-CyberPurple-Depth.imageset/Island-CyberPurple-Depth.png"
    ),
]

let assetsDir = "Sources/Ainkrad/Resources/Assets.xcassets"
let previewDir = "/private/tmp/claude-501/-Users-ahmedmelhalaby-Herd-Ainkrad/f8b02815-0732-4937-ba67-2f04aebc016d/scratchpad"

let writePreview = CommandLine.arguments.contains("--preview")

// MARK: - CoreImage pipeline

let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

func loadCIImage(path: String) -> CIImage {
    guard let img = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
        fatalError("Failed to load image at \(path)")
    }
    return img
}

/// Builds the depth map for a single source CIImage, per the heuristic:
/// 1. Desaturate + boost contrast (bright -> near, dark -> far)
/// 2. Radial gradient multiply (outer edges recede)
/// Builds a STRUCTURAL depth map (not luminance-driven). The shader
/// displaces pixels by (depth - 0.5) * offset, so:
///   - white (1.0) = NEAR  -> the central citadel mass (moves most, toward viewer)
///   - mid-gray (0.5) = NEUTRAL -> the AINKRAD wordmark band (does NOT move)
///   - black (0.0) = FAR -> open sky + edges (moves opposite)
///
/// Heuristic per image:
/// 1. Base radial gradient, ~1.0 at the citadel core fading to ~0.0 by the
///    edges, gamma-shaped so the bright core stays concentrated on the
///    central citadel mass.
/// 2. Vertical emphasis: keep the upper-middle (citadel/spire) high; let the
///    very top (open sky) fall off toward far.
/// 3. Wordmark band: composite a NEUTRAL mid-gray (~0.5) over the bottom
///    ~20% so the AINKRAD text/tagline sit on the no-movement plane.
/// 4. Very-low-weight luminance modulation (<= 0.15) — subtle only.
/// 5. Gaussian blur (~28) for a smooth field (no hard rings/edges).
func buildDepthMap(from source: CIImage, extent: CGRect) -> CIImage {
    let w = extent.width
    let h = extent.height

    // 1. Base radial gradient. Center slightly above the geometric center so
    // the bright core sits on the citadel mass (which occupies the
    // upper-middle of both compositions). White core -> black edges.
    let center = CIVector(x: extent.midX, y: extent.minY + h * 0.56)
    let innerRadius = min(w, h) * 0.05
    let outerRadius = min(w, h) * 0.62

    var field = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": center,
        "inputRadius0": innerRadius,
        "inputRadius1": outerRadius,
        "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
    ])!.outputImage!.cropped(to: extent)

    // Gamma (~1.6) concentrates the bright core; power > 1 darkens midtones,
    // pulling the "near" region tighter onto the citadel.
    field = field.applyingFilter("CIGammaAdjust", parameters: [
        "inputPower": 1.6,
    ])

    // 2. Vertical emphasis: darken only the very top (open sky) toward far,
    // leaving the upper-middle citadel/spire high. Multiplied in. The
    // gradient runs white at ~78% height up to ~0.55 at the very top; below
    // 78% it clamps to white (no change).
    let topBias = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: extent.midX, y: extent.minY + h * 0.78),
        "inputPoint1": CIVector(x: extent.midX, y: extent.maxY),
        "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        "inputColor1": CIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1),
    ])!.outputImage!.clampedToExtent().cropped(to: extent)

    field = field.applyingFilter("CIMultiplyCompositing", parameters: [
        kCIInputBackgroundImageKey: topBias,
    ])

    // 3. Optional very-low-weight luminance modulation (<= 0.15). Desaturate
    // the source, then blend it in at 0.12 opacity as a subtle structural
    // hint (bright citadel detail nudges slightly nearer). Must not dominate.
    let mono = source
        .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        .applyingFilter("CIColorMatrix", parameters: [
            // scale alpha to 0.12 so source-over blends at low weight
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.12),
        ])
        .clampedToExtent()
        .cropped(to: extent)

    field = mono.applyingFilter("CISourceOverCompositing", parameters: [
        kCIInputBackgroundImageKey: field,
    ])

    // 4. Wordmark band: composite a NEUTRAL mid-gray (~0.5) over the bottom
    // ~20% so the AINKRAD text/tagline sit on the no-movement plane and stay
    // stable. Soft-edged via an alpha gradient (full at the bottom, fading
    // out by ~24% height) so there is no hard seam. NOT black.
    let neutral = CIFilter(name: "CIConstantColorGenerator", parameters: [
        kCIInputColorKey: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
    ])!.outputImage!.cropped(to: extent)

    let bandMask = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: extent.midX, y: extent.minY + h * 0.12),
        "inputPoint1": CIVector(x: extent.midX, y: extent.minY + h * 0.26),
        "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
    ])!.outputImage!.clampedToExtent().cropped(to: extent)

    field = neutral.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: field,
        kCIInputMaskImageKey: bandMask,
    ])

    // 5. Gaussian blur to smooth the depth field; hard edges tear under
    // displacement. Re-clamp before blur to avoid transparent-edge bleed,
    // then crop back down to the original extent.
    let blurred = field.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
        kCIInputRadiusKey: 28.0,
    ]).cropped(to: extent)

    return blurred
}

func renderGrayscalePNG(_ image: CIImage, extent: CGRect, to path: String) {
    guard let cgImage = ciContext.createCGImage(
        image,
        from: extent,
        format: .L8,
        colorSpace: CGColorSpaceCreateDeviceGray()
    ) else {
        fatalError("Failed to render CGImage for \(path)")
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(path)")
    }

    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! pngData.write(to: url)
    print("Wrote \(path)")
}

func writePreviewComposite(art: CIImage, depth: CIImage, extent: CGRect, name: String) {
    let depthRGB = depth.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0.0,
    ])

    let gap: CGFloat = 8
    let width = extent.width * 2 + gap
    let height = extent.height
    let canvasExtent = CGRect(x: 0, y: 0, width: width, height: height)

    let artPositioned = art.cropped(to: extent)
    let depthPositioned = depthRGB.cropped(to: extent)
        .transformed(by: CGAffineTransform(translationX: extent.width + gap, y: 0))

    let composite = depthPositioned.composited(over: artPositioned)

    guard let cgImage = ciContext.createCGImage(composite, from: canvasExtent) else {
        fatalError("Failed to render preview composite for \(name)")
    }

    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode preview PNG for \(name)")
    }

    let path = "\(previewDir)/island-depth-preview-\(name).png"
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try! pngData.write(to: url)
    print("Wrote preview \(path)")
}

// MARK: - Main

let repoRoot = FileManager.default.currentDirectoryPath

for source in sources {
    let sourcePath = "\(repoRoot)/\(assetsDir)/\(source.sourceImageset)"
    let depthPath = "\(repoRoot)/\(assetsDir)/\(source.depthImageset)"

    print("Processing \(source.name)...")
    let art = loadCIImage(path: sourcePath)
    let extent = art.extent

    let depth = buildDepthMap(from: art, extent: extent)
    renderGrayscalePNG(depth, extent: extent, to: depthPath)

    if writePreview {
        writePreviewComposite(art: art, depth: depth, extent: extent, name: source.name)
    }
}

print("Done.")
