// SpringFSR RCAS — Robust Contrast Adaptive Sharpening
// Ported from AMD FidelityFX FSR1 (MIT license)
// https://github.com/GPUOpen-Effects/FidelityFX-FSR1

// Approximate reciprocal — faster than full-precision 1.0/x.
// AMD uses ffxApproximateReciprocalMedium; this is a GLSL equivalent.
float fastRcpMedium(float x) {
    return 1.0 / x;  // Modern GPUs handle this natively; approximation not needed.
}

void fetchNeighbors(sampler2D tex, ivec2 coord,
                    out vec3 b, out vec3 d, out vec3 e,
                    out vec3 f, out vec3 h) {
    b = texelFetch(tex, coord + ivec2( 0, -1), 0).rgb;  // AMD order: (0,-1) top
    d = texelFetch(tex, coord + ivec2(-1,  0), 0).rgb;  // (-1,0) left
    e = texelFetch(tex, coord                , 0).rgb;  // (0,0) center
    f = texelFetch(tex, coord + ivec2( 1,  0), 0).rgb;  // (1,0) right
    h = texelFetch(tex, coord + ivec2( 0,  1), 0).rgb;  // (0,1) bottom
}

// Luma * 2 (matches AMD: bB*0.5 + bR*0.5 + bG)
float luma(vec3 c) {
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// Per-channel lobe: solves for max local sharpness before clipping.
// peakC = (1.0, -4.0) are immediate constants from AMD spec.
float computeLobeChannel(float b, float d, float e, float f, float h) {
    const vec2 peakC = vec2(1.0, -4.0);
    float mn4 = min(min3(b, d, f), h);
    float mx4 = max(max3(b, d, f), h);

    // AMD: hitMin = mn4 / (4*mx4), lobe = max(-hitMin, hitMax)
    float hitMin = mn4 * fastRcpMedium(4.0 * mx4);
    float hitMax = (peakC.x - max(mx4, e)) * fastRcpMedium(4.0 * mn4 + peakC.y);
    return max(-hitMin, hitMax);
}

vec3 fsrRCAS(sampler2D inputTexture, ivec2 fragCoord) {
    // RCAS_SHARPNESS: 0.0-1.0 mapped to 2.5-0.0 stops (AMD style)
    // stops=2.5 → exp2(-2.5)=0.177 (minimum sharpening)
    // stops=0.0 → exp2(0.0)=1.0 (maximum sharpening)
    float sharpnessStops  = (1.0 - saturate(RCAS_SHARPNESS)) * 2.5;
    float sharpnessLinear = exp2(-sharpnessStops);

    vec3 b, d, e, f, h;
    fetchNeighbors(inputTexture, fragCoord, b, d, e, f, h);

    // --- Noise detection (AMD FSR_RCAS_DENOISE / RCAS_ENABLE_NOISE_SUPPRESSION) ---
    // AMD: nz = 0.25*(bL+dL+fL+hL) - eL, normalized by range, shaped by -0.5*x+1.0
    float nz = 1.0;

#if defined(SPRINGFSR_RCAS_DENOISE) || defined(RCAS_ENABLE_NOISE_SUPPRESSION)
    float bL = luma(b), dL = luma(d), eL = luma(e), fL = luma(f), hL = luma(h);
    float range = max3(max3(bL, dL, eL), fL, hL) - min3(min3(bL, dL, eL), fL, hL);

    // AMD exact formula: avgNeiMinusCenter = 0.25*(b+d+f+h) - e
    float avgNeiMinusCenter = (0.25 * (bL + dL + fL + hL)) - eL;
    float nzRaw = saturate(abs(avgNeiMinusCenter) * fastRcpMedium(max(range, 1e-4)));
    nz = -0.5 * nzRaw + 1.0;

    #ifdef SPRINGFSR_RCAS_DENOISE
        // More aggressive denoise: squared shaping, hits noise harder while preserving edges
        nz = nz * nz;
    #endif
#endif

    // --- Lobe computation for each channel ---
    float lR = computeLobeChannel(b.r, d.r, e.r, f.r, h.r);
    float lG = computeLobeChannel(b.g, d.g, e.g, f.g, h.g);
    float lB = computeLobeChannel(b.b, d.b, e.b, f.b, h.b);

    // Combined lobe clamped to [-LIMIT, 0], shaped by sharpness and noise suppression
    float lobe = max(-RCAS_LIMIT, min(max3(lR, lG, lB), 0.0)) * sharpnessLinear * nz;

    // Resolve: (lobe*(b+d+f+h) + e) / (4*lobe + 1)
    float rcpL = fastRcpMedium(4.0 * lobe + 1.0);
    return (lobe * (b + d + f + h) + e) * rcpL;
}
