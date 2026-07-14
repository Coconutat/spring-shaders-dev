// FSR2-style Depth Clip for TAA
// Ported from AMD FidelityFX FSR2 v2.3.3 (MIT license)
//
// Detects when reprojected history pixel is occluded by a closer surface,
// and reduces history weight accordingly. Eliminates ghosting at disocclusion boundaries.
//
// Note: linearizeDepth() is defined in lib/common/position.glsl — not redefined here.

// Depth clip confidence: 0.0 = disoccluded (don't trust history), 1.0 = consistent
// Compares current depth with reprojected previous-frame depth using bilinear weights.
float depthClipConfidence(vec2 uv, vec2 velocity, float currentDepth) {
    float currDist = linearizeDepth(currentDepth);

    // Reproject to previous frame
    vec2 reprojectedUV = uv - velocity;
    if (outScreen(reprojectedUV)) return 0.0;

    // Get 4 bilinear taps around the reprojected position
    vec2 texelCoord = reprojectedUV * viewSize - 0.5;
    vec2 baseTexel = floor(texelCoord);

    float depthSum = 0.0;
    float weightSum = 0.0;

    for (int i = 0; i < 4; i++) {
        vec2 sampleTexelCoord = baseTexel + vec2(float(i & 1), float(i >> 1));
        vec2 clamped = clamp(sampleTexelCoord, vec2(0.0), viewSize - 1.0);

        // Bilinear weight
        float bilinearWeight = (1.0 - abs(texelCoord.x - sampleTexelCoord.x))
                             * (1.0 - abs(texelCoord.y - sampleTexelCoord.y));
        if (bilinearWeight < 0.01) continue;

        // Clamp to screen bounds
        if (clamped == sampleTexelCoord) {
            ivec2 sampleTexel = ivec2(sampleTexelCoord);

            // Read previous frame depth from colortex6.b (HRR depth, written by composite pass)
            // colortex6 is RG32F: r=packed normal, g=depth
            float prevDepth = texelFetch(colortex6, sampleTexel, 0).g;
            float prevDist = linearizeDepth(prevDepth);

            float distDiff = currDist - prevDist;

            if (distDiff > 0.0) {
                // Current pixel is farther than reprojected position → potential disocclusion
                // FSR2 formula: depth separation threshold based on viewport size and FOV
                float planeDepth = max(prevDepth, currentDepth);

                vec3 center = (gbufferProjectionInverse * vec4(0.0, 0.0, planeDepth * 2.0 - 1.0, 1.0)).xyz;
                vec3 corner = (gbufferProjectionInverse * vec4(-1.0, -1.0, planeDepth * 2.0 - 1.0, 1.0)).xyz;
                center /= center.z;
                corner /= corner.z;

                float halfViewportWidth = length(viewSize);
                float depthThreshold = max(currDist, prevDist);

                const float sepFactor = 1.37e-05;
                float fovFactor = length(center) / length(corner);
                float requiredDepthSeparation = sepFactor * fovFactor * halfViewportWidth * depthThreshold;

                float power = 2.0; // Simplified from FSR2's resolution-adaptive power
                float confidence = pow(saturate(requiredDepthSeparation / max(distDiff, 1e-6)), power);

                depthSum += confidence * bilinearWeight;
                weightSum += bilinearWeight;
            } else {
                // Current pixel is closer or same distance → trust history
                depthSum += 1.0 * bilinearWeight;
                weightSum += bilinearWeight;
            }
        }
    }

    return (weightSum > 0.0) ? saturate(depthSum / weightSum) : 0.0;
}
