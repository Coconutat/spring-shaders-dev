// FSR3-style Sphere Clip for TAA history convergence
// Replaces AABB clipping with sphere-based convergence.
// Sphere is less prone to color shifting and converges faster
// than axis-aligned box, especially on diagonal motion.
//
// Reference: AMD FidelityFX FSR3 Upscaler v3.1.4

// Clip history color using a sphere instead of AABB.
// Returns clipped preColor in YCoCgR space.
//
// nowColor  — current frame color in YCoCgR (center of neighborhood stats)
// preColor  — history frame color in YCoCgR (to be clipped)
// sigma     — standard deviation of 3x3 neighborhood (from AABB function)
// gamma     — clip multiplier (same as TAA_VARIANCE_CLIP_GAMMA)
vec3 clipSphere(vec3 nowColor, vec3 preColor, vec3 sigma, float gamma) {
    // Sphere center = current pixel (after tonemap, in YCoCgR)
    // Radius = length of sigma * gamma (instead of per-axis half-extents)
    vec3 clipCenter = nowColor;
    float radius = length(sigma) * gamma;

    // If history is inside sphere, use as-is
    vec3 clipDir = preColor - clipCenter;
    float clipDist = length(clipDir);

    if (clipDist > radius && radius > 1e-6) {
        // Project history onto sphere surface
        return clipCenter + clipDir * (radius / clipDist);
    }
    return preColor;
}
