varying vec2 texcoord;

#include "/lib/uniform.glsl"
#include "/lib/settings.glsl"
#include "/lib/common/utils.glsl"
#include "/lib/common/position.glsl"
#include "/lib/camera/colorToolkit.glsl"
#include "/lib/camera/toneMapping.glsl"

#ifdef FSH

// composite14 only needs EASU, not the full SpringFSR suite
#include "/lib/SpringFSR/EASU.glsl"

void main() {
    float renderScale = 1.0;
    #if SPRINGFSR_MODE == 1
        renderScale = 0.77;
    #elif SPRINGFSR_MODE == 2
        renderScale = 0.67;
    #elif SPRINGFSR_MODE == 3
        renderScale = 0.50;
    #elif SPRINGFSR_MODE == 4
        renderScale = 0.33;
    #endif

    // EASU from CT0 (full-res, no perf gain without buffer scaling)
    vec2 inputSize = viewSize * renderScale;
    vec3 color = fsrEasu(colortex0, gl_FragCoord.xy, inputSize, viewSize);

    // Tonemap HDR→LDR
    color = max(TONE_MAPPING(color), vec3(0.0));

/* RENDERTARGETS: 14 */
    gl_FragData[0] = vec4(color, 1.0);
}

#endif

#ifdef VSH

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif
