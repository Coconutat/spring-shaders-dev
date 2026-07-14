// SpringFSR Luma Instability — FSR3-style luminance instability detection
// Detects pixels whose luminance fluctuates rapidly between frames.
// High instability → reduce accumulation weight to prevent flicker buildup.
//
// Reference: AMD FidelityFX FSR3 Upscaler v3.1.4

// Compute luma instability value: 0.0 = stable, 1.0 = highly unstable
// currentLuma — tonemapped luma of current frame pixel
// prevLuma    — tonemapped luma of reprojected history pixel
// lockValue   — current lock value (0-1), from SPRINGFSR_LOCK if enabled
float lumaInstability(float currentLuma, float prevLuma, float lockValue) {
    float lumaDiff = abs(currentLuma - prevLuma);

    // Normalize by max luma to get relative change
    float maxLuma = max(currentLuma, prevLuma);
    float relDiff = lumaDiff / max(maxLuma, 1e-4);

    // FSR3-style: smoothstep shapes the response curve
    // Small diffs (<0.02) = noise, ignored
    // Large diffs (>0.15) = full instability
    float instability = smoothstep(0.02, 0.15, relDiff);

    // Locked pixels shouldn't show instability (they're trusted)
    // But if a locked pixel suddenly has high instability, something changed
    // → force unlock by keeping instability high
    instability = mix(instability, 1.0, instability * lockValue * 0.5);

    return saturate(instability);
}

// Apply instability to blend factor
// blendFactor: original blend factor from TAA
// instability: 0.0-1.0 from lumaInstability()
// Returns: adjusted blend factor (up to 2x for unstable pixels)
float applyInstability(float blendFactor, float instability) {
    return blendFactor * (1.0 + instability);
}
