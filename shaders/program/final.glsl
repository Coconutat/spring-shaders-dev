// ===== SR MOD Debug =====
// 启用后左上角显示 3 个状态色块，调试完成后注释此行即可关闭
#define SR_DEBUG
// =========================

varying vec2 texcoord;



#include "/lib/uniform.glsl"
#include "/lib/settings.glsl"
#include "/lib/common/utils.glsl"

#include "/lib/camera/colorToolkit.glsl"
#include "/lib/camera/toneMapping.glsl"
#include "/lib/camera/filter.glsl"
#include "/lib/common/noise.glsl"

#include "/lib/common/position.glsl"
#include "/lib/common/normal.glsl"
#include "/lib/camera/exposure.glsl"

#ifdef FSH

const bool shadowtex0Mipmap = false;
const bool shadowtex1Mipmap = false;
const bool shadowcolor0Mipmap = false;
const bool shadowcolor1Mipmap = false;

#include "/lib/camera/postFX.glsl"
#include "/lib/camera/depthOfField.glsl"
#include "/lib/antialiasing/FSR.glsl"

vec3 sRGBEncodeSafe(vec3 c) {
	vec3 s = sign(c);
	c = abs(c);

	bvec3 cutoff = lessThan(c, vec3(0.0031308));
	vec3 higher = vec3(1.055) * pow(c, vec3(1.0 / 2.4)) - vec3(0.055);
	vec3 lower = c * vec3(12.92);
	c = mix(higher, lower, cutoff);

	return c * s;
}


void main() {
	// SR_INSTALLED 时由 Super Resolution Mod 接管锐化，避免双重锐化
	#if defined(FSR_RCAS) && !defined(SR_INSTALLED)
		vec4 color = vec4(fsrRCAS(colortex0, ivec2(gl_FragCoord.xy)), 1.0);
	#else
		vec4 color = max(texture(colortex0, texcoord), 0.0);
	#endif

	#if defined(HDR_MOD_INSTALLED) && defined(HDR_ENABLED)
		color.rgb *= HdrGamePaperWhiteBrightness / max(HdrUIBrightness, 1.0);
		color.rgb = sRGBEncodeSafe(color.rgb);
	#else
		toGamma(color);
	#endif

	#ifdef LETTER_BOX
		color.rgb = applyLetterbox(color.rgb, LETTER_BOX_SIZE);
	#endif

	// color.rgb = 10.0 * texelFetch(colortex7, lightColorUV, 0).rgb;

	
	
	// color.rgb = drawTransmittanceLut1();
	// color.rgb = drawMultiScatteringLut();
	// color.rgb = textureORB(depthtex2, texcoord).rgb;
	// color.rgb = getNormal(texcoord);
	// color.rgb = normalize(viewPosToWorldPos(vec4(color.rgb, 0.0)).xyz);
	// color.rgb = texture(colortex6, texcoord).xyzypanda;
	// color.rgb = textureLod(shadowcolor0, texcoord, 0.0).rgb;
	// color.rgb = vec3(textureLod(shadowcolor1, texcoord, 0.0));
	// color.rgb = normalize((shadowProjection * vec4(color.rgb, 0.0)).xyz);
	// color.rgb = texture(colortex10, texcoord).xyz;
	
	// color.rgb = getSpecularTex(texcoord).rgb;
	// color.rgb = vec3(temporalBayer64(gl_FragCoord.xy));
	// color.rgb = vec3(temporalBayer64(gl_FragCoord.xy));
	// color.rgb = vec3(textureLod(shadowtex1, texcoord, 0).r);
	
/* RENDERTARGETS: 0 */
	#if defined(HDR_MOD_INSTALLED) && defined(HDR_ENABLED)
		gl_FragData[0] = vec4(color.rgb, 1.0);
	#else
		gl_FragData[0] = saturate(vec4(color.rgb, 1.0));
	#endif

	// ===== SR Debug 色块（左上角）=====
	#ifdef SR_DEBUG
	{
		ivec2 p = ivec2(gl_FragCoord.xy);
		int y = int(viewSize.y);

		// 色块 1: SR_INSTALLED   — 🟢已安装 / 🔴未安装
		if (p.x < 16 && p.y > y - 16 && p.y <= y - 8) {
			#ifdef SR_INSTALLED
				color.rgb = vec3(0.0, 1.0, 0.0);
			#else
				color.rgb = vec3(1.0, 0.0, 0.0);
			#endif
		}
		// 色块 2: SR_ENABLE      — 🟡已启用 / ⚫未启用
		if (p.x < 16 && p.y > y - 32 && p.y <= y - 24) {
			#if defined(SR_ENABLE) && SR_ENABLE == 1
				color.rgb = vec3(1.0, 1.0, 0.0);
			#else
				color.rgb = vec3(0.25, 0.25, 0.25);
			#endif
		}
		// 色块 3: 抖动源          — 🔵SR抖动 / 🟣Halton回退
		if (p.x < 16 && p.y > y - 48 && p.y <= y - 40) {
			#ifdef SR_INSTALLED
				color.rgb = vec3(0.0, 0.5, 1.0);
			#else
				color.rgb = vec3(0.5, 0.0, 0.5);
			#endif
		}
	}
	#endif
	// ===== SR Debug End =====

}

#endif
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//////Z///////////////////////////////////////////////////////////////////////////////////////////////////////////////////Y///////////
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#ifdef VSH

void main() {
	gl_Position = ftransform();
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}

#endif
