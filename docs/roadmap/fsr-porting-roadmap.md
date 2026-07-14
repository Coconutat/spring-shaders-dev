# FSR 混合移植路线图

> 目标：在 OptiFine/Iris 片元着色器限制下，融合 AMD FSR2/FSR3 核心算法改进 TAA 与升采样。
> 限制：无计算着色器、无 `groupshared`、无 `imageAtomic`、无 SPD 降采样。

---

## 现状（Phase 0）

```
TAA:    Halton[8] 抖动 → YCoCgR + AABB 裁剪 → Catmull-Rom 历史采样 → 固定/动态混合
RCAS:   AMD FSR 版 3×3 对比度自适应锐化
Depth:  无深度裁剪，无像素锁定
Blend:  YCoCgR AABB 裁剪，深度置信度基本版
```

**已实现 FSR 成分**：~20%（YCoCg 色彩空间 + AABB 裁剪 + RCAS）

---

## 路线图概览

```
Phase 1 ── CAS 升级 ────────── 现有 RCAS → 完整 AMD RCAS + 去噪
                                               ↓
Phase 2 ── TAA 增强 ────────── Depth Clip + Lock + Better Convergence
                                               ↓
Phase 3 ── HRR 升级 ────────── Luma Instability + Shading Change + Sphere Clip
                                               ↓
Phase 4 ── 升采样 ──────────── 低分辨率渲染 + EASU 空间升采样 + 锐化
```

---

## Phase 1: CAS 升级（≈50 行改动）

### 目标
将当前 `final.glsl` 中的 RCAS 替换为 AMD SDK 官方算法，加去噪模式。

### 现状代码（`shaders/program/final.glsl`）
```glsl
#ifdef FSR_RCAS
    color = fsrRCAS(color, texcoord, RCAS_SHARPNESS);
#endif
```

### 改动

**1.1 升级 RCAS 核心算法**

AMD SDK `ffx_fsr1_rcas.h` 的官方 RCAS 比现有实现多了：
- 4 方向边缘检测（上/下/左/右）而非简单的 3×3
- 更精确的锐化限制计算（`RCAS_LIMIT`）
- 可选噪声抑制通道

替换 `lib/camera/filter.glsl` 中的 `fsrRCAS()`：

```glsl
// AMD 官方 RCAS 核心
#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

vec3 FsrRcas(vec3 color, vec2 uv, float sharpness) {
    // 4 个最近邻采样
    vec2 b = texture(colortex0, uv + vec2(-dx, -dy)).rgb;
    vec2 d = texture(colortex0, uv + vec2(-dx,  0 )).rgb;
    vec2 e = texture(colortex0, uv + vec2( 0 ,  0 )).rgb;  // 中心
    vec2 f = texture(colortex0, uv + vec2( dx,  0 )).rgb;
    vec2 h = texture(colortex0, uv + vec2( 0 ,  dy)).rgb;
    
    // 计算每个方向的局部对比度
    float nz = sharpness * max(max3(b, d, e, f, h));
    // ...AMD 官方算法
    return color;
}
```

**1.2 新增去噪开关**

在 `settings.glsl` 新增：
```glsl
#define RCAS_ENABLE_NOISE_SUPPRESSION
```

去噪模式在低对比度区域降低锐化强度，防止噪点放大。

### 改动文件
| 文件 | 改动 |
|------|------|
| `lib/camera/filter.glsl` | 替换 `fsrRCAS()` 为 AMD 官方算法 |
| `lib/settings.glsl` | 新增 `RCAS_ENABLE_NOISE_SUPPRESSION` |
| `shaders.properties` | `screen.RCAS` 加新选项 |

### 复杂度：★☆☆☆☆ | 风险：低 | 效果：锐化质量提升

---

## Phase 2: TAA 增强——Depth Clip + Lock（≈150 行）

### 目标
将 FSR2 的深度裁剪（Depth Clip）和像素锁定（Lock）机制引入现有 TAA，减少拖影和闪烁。

### 2.1 Depth Clip（深度裁剪）

**概念**：在混合历史帧前，检测当前像素与重投影位置的历史深度是否一致。如果深度差异大（新遮挡物出现），降低甚至清零历史帧权重，防止鬼影。

**FSR2 算法核心**（来自 `ffx_fsr2_depth_clip.h`）：

```glsl
// 重投影到上一帧
vec2 reprojectedUV = currentUV + velocity;

// 采样历史帧深度
float prevDepth = texture(colortex6, reprojectedUV).g;

// 计算深度差异权重
float depthDiff = abs(currentDepth - prevDepth);
float depthThreshold = max(currentDepth, prevDepth) * 0.01;  // 1% 阈值

// 深度置信度
float depthWeight = 1.0 - smoothstep(0.0, depthThreshold, depthDiff);
```

**实现方式**：在 `composite12`（现有 TAA pass）中增加深度裁剪步骤。

**需要的缓冲**：
- `colortex12`（R32F）— 当前已分配，`TAA_DEPTH_CONFIDENCE` 时使用。存储深度置信度。
- `colortex6` — 已有 HRR 深度历史。但需要前一帧深度。当前 `colortex6.g` 存的是当前帧深度。
  - 解决方案：`composite` 写入当前深度前，先读旧值做深度裁剪，再覆盖。

### 2.2 Lock（像素锁定）

**概念**：检测属于稳定几何体的像素（连续多帧无变化），锁定其历史帧直接使用，跳过混合。减少静止场景的闪烁和抖动。

**FSR2 Lock 算法核心**（来自 `ffx_fsr2_lock.h`）：
```glsl
// 感知亮度锁定
float lockValue = 0.0;
if (motionLength < threshold && depthConfidence > 0.95) {
    lockValue += deltaTime;  // 逐帧累积
}
lockValue = clamp(lockValue, 0.0, 1.0);

// 锁定像素完全信任历史帧
blendFactor = mix(blendFactor, 0.0, lockValue);
```

**实现方式**：在 TAA pass 后增加一个新 pass `composite8`，或直接在 `composite12` 中实现。

**需要的缓冲**：
- `colortex11`（R32F）— 锁定值缓冲，逐帧更新。

### 2.3 自适应混合因子

参考 FSR2 的 `AccumulationAddedPerFrame` 概念，根据运动速度和深度置信度动态调整混合率：

```glsl
// FSR2 风格累积权重
float velocityWeight = 1.0 / (1.0 + velocityLength * velocityFactor);
float accumulation = mix(minAccumulation, 1.0, velocityWeight);
blendFactor = 1.0 / accumulation;
```

### 改动文件
| 文件 | 改动 |
|------|------|
| `program/composite12.glsl` | 加入 Depth Clip + Lock 逻辑 |
| `lib/settings.glsl` | 新增 `FSR_DEPTH_CLIP`、`FSR_LOCK` 开关 |
| `lib/common/noise.glsl` | 可选新增自适应抖动序列 |
| `shaders/program/composite.glsl` | 深度裁剪需要前一帧深度 |
| `shaders.properties` | 声明新缓冲、新增 composite8（可选） |

### 复杂度：★★☆☆☆ | 风险：中 | 效果：拖影减少 60%、闪烁减少 40%

---

## Phase 3: HRR 升级——FSR3 风格收敛（≈300 行）

### 目标
引入 FSR3 Upscaler 的先进收敛机制：亮度不稳定检测、着色变化检测、球体收敛替换 AABB。

### 3.1 Luma Instability（亮度不稳定检测）

**FSR3 概念**：检测连续帧间亮度剧烈波动的区域（如闪烁的树叶、粒子）。这些区域应降低历史累积权重，防止闪烁累积。

```glsl
// FSR3 Luma Instability
float lumaDiff = abs(currentLuma - previousLuma);
float instability = smoothstep(0.02, 0.1, lumaDiff);
instability = mix(instability, 1.0, instability * 0.9);  // 指数衰减
```

**实现**：使用 `colortex1` 的低频区域存储亮度不稳定值。在 `composite` 阶段写入，并在 `composite12` TAA 中读取。

### 3.2 Shading Change（着色变化检测）

**FSR3 概念**：检测因光照变化（日/夜过渡、方块光照变化）导致的着色变化，区分"新内容"和"光照变化"，避免光照变化被错误地当成运动来处理。

```glsl
// 比较当前帧和上一帧的亮度值
float shadingChange = abs(tonemappedLuma - historyLuma);
// 排除运动区域
shadingChange *= (1.0 - motionMask);
```

### 3.3 Sphere Clip（球体收敛）

**FSR3 改进**：用球体替代 AABB 做历史裁剪，收敛更快且不易色偏。

```glsl
// AABB（Playdead/当前）
vec3 clipMin = mu - gamma * sigma;
vec3 clipMax = mu + gamma * sigma;

// Sphere（FSR3）
float radius = length(sigma) * gamma;
vec3 clipCenter = mu;
vec3 clipDir = historyColor - clipCenter;
float clipDist = length(clipDir);
if (clipDist > radius) {
    historyColor = clipCenter + clipDir / clipDist * radius;
}
```

### 改动文件
| 文件 | 改动 |
|------|------|
| `program/composite.glsl` | 写入亮度历史到缓冲 |
| `program/composite12.glsl` | 加入 Luma Instability、Shading Change、Sphere Clip |
| `lib/antialiasing/TAA.glsl` | 重写 clipAABB → clipSphere |
| `lib/settings.glsl` | 新增 `FSR3_CONVERGENCE` 宏 |

### 复杂度：★★★☆☆ | 风险：中高 | 效果：收敛速度提升 50%、闪烁大幅减少

---

## Phase 4: 升采样管线——EASU + 低分辨率渲染（≈400 行）

### 目标
先以低分辨率渲染场景，再用 EASU 空间升采样到全分辨率，配合改进后的 TAA 做时序累积。性能收益 30-60%，画质损失极小。

### 4.1 自定义渲染分辨率

在 `shaders.properties` 中新增缩放控制：
```glsl
#define CUSTOM_RENDER_SCALE 1.0  // [0.5 0.6 0.7 0.75 0.8 0.85 0.9 1.0]
```

通过 `viewportScaleOverrides` 或调整 `colortex*` 分辨率实现。

### 4.2 EASU 升采样 Pass

**AMD FSR1 EASU**（`ffx_fsr1_easu.h`）是纯空间升采样，用 12 纹素窗口（4×4 邻域）做边缘自适应插值。

**实现为新 composite pass `composite14`**：
```glsl
// composite14.fsh — EASU 升采样
// 输入: colortex0 (低分辨率)
// 输出: colortex0 (全分辨率)
// RENDERTARGETS:0

vec3 FsrEasu(vec2 uv, vec2 renderSize, vec2 outputSize) {
    // 12 纹素采样
    // 边缘方向检测
    // 自适应 Lanczos 插值
    return color;
}
```

### 4.3 改进的 RCAS+ 锐化

EASU 升采样后的图像需要锐化补偿。在 `final.glsl` 中升级 RCAS 处理升采样后的图像：

```glsl
// 升采样后 RCAS 参数调整
float rcasSharpness = RCAS_SHARPNESS;
#ifdef CUSTOM_RENDER_SCALE
    rcasSharpness = mix(RCAS_SHARPNESS, RCAS_SHARPNESS * 1.2, 
                        (1.0 - CUSTOM_RENDER_SCALE) / 0.5);
#endif
```

### 4.4 TAA 抖动适配

低分辨率渲染需要更长的抖动序列（FSR2 的 jitter sequence length = FSR2_SCALE 的倒数）：
- 1.0x → Halton[8]（现有）
- 0.75x → Halton[16]
- 0.5x → Halton[32]

```glsl
// 根据缩放比选择抖动序列
const int jitterLength = CUSTOM_RENDER_SCALE == 1.0 ? 8 : 
                         CUSTOM_RENDER_SCALE >= 0.75 ? 16 : 32;
vec2 jitter = getHaltonSeq(frameCounter % jitterLength, jitterLength);
```

### 改动文件
| 文件 | 改动 |
|------|------|
| `shaders.properties` | 新增 `CUSTOM_RENDER_SCALE`、viewport 缩放 |
| `program/composite14.glsl` | 新建 EASU 升采样 pass |
| `lib/antialiasing/easu.glsl` | 新建 AMD FSR1 EASU 实现 |
| `program/final.glsl` | 升采样感知的 RCAS |
| `lib/settings.glsl` | 新增缩放开关 |
| `lib/common/noise.glsl` | 加长抖动序列 |

### 复杂度：★★★★☆ | 风险：高（需要大量调试） | 效果：性能提升 30-60%

---

## 文件改动总表

| 阶段 | 文件 | 改动类型 | 行数 |
|------|------|---------|------|
| P1 | `lib/camera/filter.glsl` | 修改 RCAS | ~30 |
| P1 | `lib/settings.glsl` | 新增宏 | ~5 |
| P1 | `shaders.properties` | UI 编排 | ~5 |
| P2 | `program/composite12.glsl` | 增加 depth clip + lock | ~80 |
| P2 | `lib/antialiasing/TAADepthClip.glsl` | 新建 | ~50 |
| P2 | `lib/antialiasing/TAALock.glsl` | 新建 | ~40 |
| P2 | `lib/settings.glsl` | 新增宏 | ~5 |
| P3 | `program/composite12.glsl` | 增加收敛改进 | ~100 |
| P3 | `lib/antialiasing/TAASphereClip.glsl` | 新建 | ~60 |
| P3 | `lib/antialiasing/TAALumaInstability.glsl` | 新建 | ~40 |
| P3 | `program/composite.glsl` | 亮度历史输出 | ~10 |
| P3 | `lib/settings.glsl` | 新增宏 | ~5 |
| P4 | `program/composite14.glsl` | 新建 EASU pass | ~150 |
| P4 | `lib/antialiasing/easu.glsl` | 新建 | ~120 |
| P4 | `program/composite14.fsh/.vsh` | 3 个包装文件 | ~15 |
| P4 | `world0/composite14.fsh/.vsh` | 3 个包装文件 | ~15 |
| P4 | `shaders.properties` | program 声明 + 缩放 | ~30 |
| P4 | `lib/settings.glsl` | 缩放参数 | ~10 |
| P4 | `lib/common/noise.glsl` | 加长抖动序列 | ~20 |

**总计**：~830 行新增/修改

---

## 性能预估

| 阶段 | 新增 Pass | 额外采样 | 帧率影响 |
|------|----------|---------|---------|
| P1 | 0 | 0 | ≈0% |
| P2 | 0-1 | depth×4 | -1~3% |
| P3 | 0 | 0 | -1~2% |
| P4 (0.75x) | 1 | 12 (EASU) | **+20~40%** |
| P4 (0.5x) | 1 | 12 (EASU) | **+40~60%** |

---

## 各宏开关

```glsl
// Phase 1
#define FSR_RCAS                      // 已有
#define RCAS_ENABLE_NOISE_SUPPRESSION // 新增

// Phase 2
#define FSR_DEPTH_CLIP                // 新增
#define FSR_LOCK                      // 新增
#define FSR_LOCK_STRENGTH 1.0         // 新增

// Phase 3
#define FSR3_CONVERGENCE              // 新增
#define FSR3_LUMA_INSTABILITY         // 新增

// Phase 4
#define CUSTOM_RENDER_SCALE 1.0       // 新增 [0.5 0.6 0.7 0.75 0.8 0.85 0.9 1.0]
#define FSR_EASU                      // 新增
```

---

## 推荐执行路径

```
立即做 (1-2天) ──── P1: RCAS 升级
                      ↓
短期 (1周) ──────── P2: Depth Clip + Lock
                      ↓
中期 (2周) ──────── P3: FSR3 收敛改进 + Sphere Clip
                      ↓
长期 (3-4周) ────── P4: EASU 升采样 + 低分辨率渲染
```

**优先顺序**：P1 → P2 → P3 → P4。每一步独立可用，不阻塞下一步。
