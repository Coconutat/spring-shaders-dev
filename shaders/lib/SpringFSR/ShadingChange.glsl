// SpringFSR Shading Change Detection — FSR3-style lighting change vs motion
// Ported from AMD FidelityFX FSR3 Upscaler (MIT license)
// and iterationRP's lock status update.
//
// Distinguishes real lighting changes (day/night transition, block light
// updates) from actual motion, preventing unnecessary lock resets during
// lighting transitions.

// Compute shading change luma from output color.
// Uses tonemapped luminance for frame-to-frame comparison.
// Returns: shading luma value (store for next frame's comparison)
float computeShadingLuma(vec3 color) {
    return getLuminance(color);
}

// Detect shading change between current and previous frame.
// currentLuma: from computeShadingLuma() for current frame
// prevLuma: stored from previous frame's computeShadingLuma()
// Returns: 0.0 = no change, 1.0 = significant shading change
float detectShadingChange(float currentLuma, float prevLuma) {
    float diff = abs(currentLuma - prevLuma);
    return smoothstep(0.02, 0.10, diff);
}

// Apply shading change factor to blend factor
// blendFactor: original TAA blend factor
// shadingChange: 0.0-1.0 from detectShadingChange()
// Returns: adjusted blend factor
float applyShadingChange(float blendFactor, float shadingChange) {
    return max(blendFactor, shadingChange * 0.08);
}
