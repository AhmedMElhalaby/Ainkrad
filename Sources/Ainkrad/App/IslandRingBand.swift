// Sources/Ainkrad/App/IslandRingBand.swift
import SwiftUI

/// An annulus (ring band) hit shape: the area between two concentric ellipses,
/// filled even-odd so only the band — not the interior — is hittable.
struct IslandRingBand: Shape {
    /// Inner radius as a fraction of the outer radius.
    var innerFraction: CGFloat = 0.72
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect)
        let iw = rect.width * innerFraction, ih = rect.height * innerFraction
        p.addEllipse(in: CGRect(x: rect.midX - iw / 2, y: rect.midY - ih / 2, width: iw, height: ih))
        return p
    }
}
