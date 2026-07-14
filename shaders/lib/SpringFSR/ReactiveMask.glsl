// SpringFSR Reactive Mask — FSR3-style transparency detection for TAA
// Ported from AMD FidelityFX FSR3 Upscaler (MIT license)
//
// Detects alpha-tested and alpha-blended regions (plants, leaves,
// water, entities) and returns a "reactive" factor.
// High reactivity → TAA trusts history less → prevents ghosting
// on transparent and thin geometry.

// Compute reactive mask from block/material ID in colortex4.g
// Returns: 0.0 = fully opaque, 1.0 = fully reactive (transparent)
float computeReactiveMask(vec2 uv) {
    float blockID = unpack16To2x8(texture(colortex4, uv).g).x * ID_SCALE;

    float reactive = 0.0;

    // Alpha-tested thin geometry (plants, tall grass, other foliage)
    if (blockID >= PLANTS_SHORT - 0.5 && blockID <= PLANTS_OTHER + 0.5)
        reactive = max(reactive, 0.35);

    // Leaves — denser alpha-tested, more ghosting prone
    if (abs(blockID - LEAVES) < 0.5)
        reactive = max(reactive, 0.4);

    // Translucent surfaces (water, ice)
    if (abs(blockID - WATER) < 0.5 || abs(blockID - ICE) < 0.5)
        reactive = max(reactive, 0.6);

    // Entities — may have alpha transparency (armor, potion effects, etc.)
    if (abs(blockID - ENTITIES) < 0.5)
        reactive = max(reactive, 0.25);

    return saturate(reactive);
}

// Apply reactive mask to TAA blend factor
// blendFactor: original blend factor
// reactive: 0.0-1.0 from computeReactiveMask()
// Returns: adjusted blend factor (up to +0.12 for full reactive)
float applyReactiveMask(float blendFactor, float reactive) {
    return max(blendFactor, reactive * 0.12);
}
