// SpringFSR EASU — FSR1 Edge Adaptive Spatial Upsampling
// Ported from AMD FidelityFX FSR1 (MIT license)
// https://github.com/GPUOpen-Effects/FidelityFX-FSR1
//
// 12-tap Lanczos2-based edge-directed upsampler.
// Reads from a scaled (lower-resolution) input and produces
// a full-resolution output with minimal blurring.

// EASU tap: accumulate weighted sample into color
void fsrEasuTap(inout vec3 aC, inout float aW, vec2 off, vec2 dir,
                vec2 len, float lob, float clp, vec3 c) {
    vec2 rotOff = vec2(dot(off, dir), dot(off, vec2(-dir.y, dir.x)));
    rotOff *= len;
    float d2 = min(dot(rotOff, rotOff), clp);
    float wB = 0.4 * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = 1.5625 * wB - 0.5625;
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

// EASU set: accumulate gradient direction and edge length from a 3x3 diamond
void fsrEasuSet(inout vec2 dir, inout float len, float w,
                float lA, float lB, float lC, float lD, float lE) {
    // X direction
    float lenX = 1.0 / max(abs(lD - lC), abs(lC - lB));
    float dirX = lD - lB;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) * lenX);
    lenX *= lenX;
    len += lenX * w;

    // Y direction
    float lenY = 1.0 / max(abs(lE - lC), abs(lC - lA));
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) * lenY);
    lenY *= lenY;
    len += lenY * w;
}

// Luma * 2 (matches AMD: b*0.5 + r*0.5 + g)
float easuLuma(vec3 c) {
    return c.b * 0.5 + (c.r * 0.5 + c.g);
}

// Main EASU upscale function
// inputTex: scaled (low-res) color buffer
// fragCoord: full-resolution output pixel position
// inputSize: size of the scaled input buffer (e.g. 1440x900)
// outputSize: full output resolution (e.g. 1920x1080)
vec3 fsrEasu(sampler2D inputTex, vec2 fragCoord,
             vec2 inputSize, vec2 outputSize) {
    vec2 sizeRatio = inputSize / outputSize;
    vec2 pp = fragCoord * sizeRatio - 0.5;
    vec2 fp = floor(pp);
    pp -= fp;
    ivec2 baseTexel = ivec2(fp);

    // 12 texel fetches: B,C,E,F,G,H,I,J,K,L,N,O
    vec3 b = texelFetch(inputTex, baseTexel + ivec2( 0, -1), 0).rgb;
    vec3 c = texelFetch(inputTex, baseTexel + ivec2( 1, -1), 0).rgb;
    vec3 e = texelFetch(inputTex, baseTexel + ivec2(-1,  0), 0).rgb;
    vec3 f = texelFetch(inputTex, baseTexel + ivec2( 0,  0), 0).rgb;
    vec3 g = texelFetch(inputTex, baseTexel + ivec2( 1,  0), 0).rgb;
    vec3 h = texelFetch(inputTex, baseTexel + ivec2( 2,  0), 0).rgb;
    vec3 i = texelFetch(inputTex, baseTexel + ivec2(-1,  1), 0).rgb;
    vec3 j = texelFetch(inputTex, baseTexel + ivec2( 0,  1), 0).rgb;
    vec3 k = texelFetch(inputTex, baseTexel + ivec2( 1,  1), 0).rgb;
    vec3 l = texelFetch(inputTex, baseTexel + ivec2( 2,  1), 0).rgb;
    vec3 n = texelFetch(inputTex, baseTexel + ivec2( 0,  2), 0).rgb;
    vec3 o = texelFetch(inputTex, baseTexel + ivec2( 1,  2), 0).rgb;

    // Luminance for each
    float bL = easuLuma(b), cL = easuLuma(c);
    float eL = easuLuma(e), fL = easuLuma(f), gL = easuLuma(g), hL = easuLuma(h);
    float iL = easuLuma(i), jL = easuLuma(j), kL = easuLuma(k), lL = easuLuma(l);
    float nL = easuLuma(n), oL = easuLuma(o);

    // Accumulate gradient direction and edge length (4 quadrants)
    vec2 dir = vec2(0.0);
    float len = 0.0;
    fsrEasuSet(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
    fsrEasuSet(dir, len,        pp.x  * (1.0 - pp.y), cL, fL, gL, hL, kL);
    fsrEasuSet(dir, len, (1.0 - pp.x) *        pp.y , fL, iL, jL, kL, nL);
    fsrEasuSet(dir, len,        pp.x  *        pp.y , gL, jL, kL, lL, oL);

    // Normalize gradient direction
    vec2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool zro = dirR < (1.0 / 32768.0);
    dirR = zro ? 1.0 : inversesqrt(dirR);
    dir.x = zro ? 1.0 : dir.x;
    dir *= dirR;

    // Edge length (squared)
    len = len * 0.5;
    len *= len;

    // Anisotropic stretch
    float stretch = dot(dir, dir) / max(abs(dir.x), abs(dir.y));
    vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);

    // Negative lobe
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;

    // Clip point
    float clp = 1.0 / lob;

    // Local min/max for anti-ringing (center 2x2: f,g,j,k)
    vec3 min4 = min(min(f, g), min(j, k));
    vec3 max4 = max(max(f, g), max(j, k));

    // Gather 12 weighted taps
    vec3 aC = vec3(0.0);
    float aW = 0.0;
    fsrEasuTap(aC, aW, vec2( 0.0, -1.0) - pp, dir, len2, lob, clp, b);
    fsrEasuTap(aC, aW, vec2( 1.0, -1.0) - pp, dir, len2, lob, clp, c);
    fsrEasuTap(aC, aW, vec2(-1.0,  0.0) - pp, dir, len2, lob, clp, e);
    fsrEasuTap(aC, aW, vec2( 0.0,  0.0) - pp, dir, len2, lob, clp, f);
    fsrEasuTap(aC, aW, vec2( 1.0,  0.0) - pp, dir, len2, lob, clp, g);
    fsrEasuTap(aC, aW, vec2( 2.0,  0.0) - pp, dir, len2, lob, clp, h);
    fsrEasuTap(aC, aW, vec2(-1.0,  1.0) - pp, dir, len2, lob, clp, i);
    fsrEasuTap(aC, aW, vec2( 0.0,  1.0) - pp, dir, len2, lob, clp, j);
    fsrEasuTap(aC, aW, vec2( 1.0,  1.0) - pp, dir, len2, lob, clp, k);
    fsrEasuTap(aC, aW, vec2( 2.0,  1.0) - pp, dir, len2, lob, clp, l);
    fsrEasuTap(aC, aW, vec2( 0.0,  2.0) - pp, dir, len2, lob, clp, n);
    fsrEasuTap(aC, aW, vec2( 1.0,  2.0) - pp, dir, len2, lob, clp, o);

    // Anti-ringing clamp
    vec3 result = aC / aW;
    return clamp(result, min4, max4);
}
