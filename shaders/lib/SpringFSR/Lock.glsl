// SpringFSR Lock — FSR2-style pixel lock for TAA
// Ported from AMD FidelityFX FSR2 v2.3.3 (MIT license)
//
// Accumulates a per-pixel "lock" value for stable geometry.
// Locked pixels fully trust history → zero blend, no flicker.
// Lock decays on motion/disocclusion → instant recovery.

// Thin feature confidence: detects whether this pixel is on a thin geometry edge
// (like wires, grass, leaves) that needs special handling.
bool thinFeatureConfidence(vec2 uv, float currentLuma) {
    const float similarThreshold = 1.1;
    float dissimilarLumaMin = 1e10;
    float dissimilarLumaMax = 0.0;

    uint mask = (1u << 4u); // bit 4 = center pixel (always similar to itself)

    // Rejection masks for 3x3: each checks a 2x2 corner cluster
    // 0 1 2
    // 3 4 5
    // 6 7 8
    const uint rejectionMasks[4] = uint[4](
        (1u << 0u) | (1u << 1u) | (1u << 3u) | (1u << 4u),  // top-left
        (1u << 1u) | (1u << 2u) | (1u << 4u) | (1u << 5u),  // top-right
        (1u << 3u) | (1u << 4u) | (1u << 6u) | (1u << 7u),  // bottom-left
        (1u << 4u) | (1u << 5u) | (1u << 7u) | (1u << 8u)   // bottom-right
    );

    int idx = 0;
    for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++, idx++) {
        if (x == 0 && y == 0) continue;

        vec2 sampleUV = uv + vec2(float(x), float(y)) * invViewSize;
        if (outScreen(sampleUV)) continue;

        float sampleLuma = getLuminance(texture(colortex0, sampleUV).rgb);
        float difference = max(sampleLuma, currentLuma) / max(min(sampleLuma, currentLuma), 1e-6);

        if (difference > 0.0 && difference < similarThreshold) {
            mask |= (1u << uint(idx));
        } else {
            dissimilarLumaMin = min(dissimilarLumaMin, sampleLuma);
            dissimilarLumaMax = max(dissimilarLumaMax, sampleLuma);
        }
    }
    }

    // Not a ridge → not a thin feature
    if (!(currentLuma > dissimilarLumaMax || currentLuma < dissimilarLumaMin))
        return false;

    // Check rejection masks: if any 2x2 corner cluster is fully similar → not thin
    for (int i = 0; i < 4; i++) {
        if ((mask & rejectionMasks[i]) == rejectionMasks[i])
            return false;
    }

    return true;
}

// Compute lock value for current pixel
// lockPrev: previous frame's lock value (0.0-1.0)
// velocity: motion vector
// depthConfidence: from depth clip (0.0=disoccluded, 1.0=consistent)
// Returns: new lock value (0.0-1.0)
float computeLock(float lockPrev, vec2 velocity, float depthConfidence, vec2 uv) {
    float velLength = length(velocity * viewSize);

    // Lock only when:
    // 1. Motion is very small (static geometry)
    // 2. Depth is consistent (no disocclusion)
    // 3. Not a thin feature edge

    float motionLock = 1.0 - smoothstep(0.5, 3.0, velLength);
    float depthLock = depthConfidence;

    // Combined lock signal
    float lockSignal = min(motionLock, depthLock);

    // Thin feature rejection
    float luma = getLuminance(texture(colortex0, uv).rgb);
    if (thinFeatureConfidence(uv, luma)) {
        lockSignal = 0.0; // Don't lock thin features (causes edge flicker)
    }

    // Accumulate: increase when stable, decay on change
    // FSR2-style: additive accumulation capped at 1.0
    float lockNew;
    if (lockSignal > 0.9) {
        // Stable: accumulate lock
        lockNew = min(lockPrev + 0.1, 1.0);
    } else if (lockSignal < 0.3) {
        // Changed: reset lock
        lockNew = 0.0;
    } else {
        // Transition: decay gradually
        lockNew = lockPrev * 0.9;
    }

    return lockNew;
}

// Apply lock to blend factor
// lock: 0.0=no lock, 1.0=fully locked
// blendFactor: original blend factor from TAA
// Returns: adjusted blend factor
float applyLock(float lock, float blendFactor) {
    // Fully locked → zero blend (100% trust history)
    // No lock → original blend factor
    return mix(blendFactor, 0.0, lock);
}
