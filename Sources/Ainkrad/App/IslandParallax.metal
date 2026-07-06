#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Displaces each pixel of the Living Island artwork by an amount read from
/// a per-image depth map (white = near, black = far), producing a cheap
/// 2.5D parallax effect without any 3D geometry. `offset` is the max
/// displacement (in layer points) applied to the nearest pixels; `baseline`
/// is the depth value that receives zero displacement (0.5 = mid-depth).
[[ stitchable ]] half4 islandParallax(float2 position,
                                      SwiftUI::Layer layer,
                                      float2 size,
                                      texture2d<float> depth,
                                      float2 offset,
                                      float baseline) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float d = depth.sample(s, position / size).r;   // 0 (far) … 1 (near)
    float2 disp = (d - baseline) * offset;          // near pixels shift most
    return layer.sample(position - disp);
}
