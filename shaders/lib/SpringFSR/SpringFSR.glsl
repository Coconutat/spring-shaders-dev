// SpringFSR — FSR-inspired upscaling & anti-aliasing for spring-shaders
// Based on AMD FidelityFX FSR1 (RCAS), FSR2 (Depth Clip, Lock),
// and FSR3 (Sphere Clip, Luma Instability).
// Ported and adapted under MIT license.
// See: https://github.com/GPUOpen-Effects/FidelityFX-FSR1
//      https://github.com/GPUOpen-Effects/FidelityFX-FSR2
//      https://github.com/GPUOpen-Effects/FidelityFX-FSR3.1

#ifdef SPRINGFSR_RCAS
    #include "/lib/SpringFSR/RCAS.glsl"
#endif

#ifdef SPRINGFSR_DEPTH_CLIP
    #include "/lib/SpringFSR/DepthClip.glsl"
#endif

#ifdef SPRINGFSR_LOCK
    #include "/lib/SpringFSR/Lock.glsl"
#endif

#ifdef SPRINGFSR_SPHERE_CLIP
    #include "/lib/SpringFSR/SphereClip.glsl"
#endif

#ifdef SPRINGFSR_LUMA_INSTABILITY
    #include "/lib/SpringFSR/LumaInstability.glsl"
#endif
