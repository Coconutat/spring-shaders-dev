# SpringFSR 管线重构路线图

> SpringFSR 模块化组件已全部实现（RCAS、DepthClip、Lock、SphereClip、LumaInstability、ReactiveMask、ShadingChange、EASU）。
> 下一步：将现有插件式模块升级为完整低分辨率渲染 + EASU 升采样管线。

---

## Pipeline Refactor — SpringFSR 3.0 (管线重构)

### 目标
将现有插件式 FSR 模块升级为完整 FSR3 风格时域升采样管线。低分辨率渲染 → EASU 升采样 → RCAS 锐化，性能提升 30-80%。

### 架构变更

#### 当前
```
GBuffer(full CT0-5,9,15) → Deferred(CT0) → Composite(TAA,CT0) → Final(CT0)
                                                                    ↑
                                                            EASU 已实现但全分辨率无增益
```

#### 目标 (P4 refactor)
```
GBuffer(full CT0-5,9,15) → CS bridge → Deferred(scaled CT6) → Composite(scaled CT6,TAA) → EASU(CT6→CT14 full) → Final(CT14)
                                                                    ↑
                                                          FSR3 RectifyHistory
                                                          FSR3 Accumulation Matrix
                                                          FSR3 Reactive from Alpha
```

### 核心改动

#### 1. CS 桥接 pass (`composite0.csh`)
新建 compute shader，在 deferred 链前执行：
- 读 GBuffer full-res: texelFetch(colortex0..5,9,15)
- 写 scaled buffers: imageStore to CT6..13,16..18
- 同时生成：Reactive from Alpha, Motion Vector Fill, Prev Depth Reconstruct

#### 2. RENDERTARGETS 修复（仅 4 个 pass）

| Pass | 现在 | 改为 | 说明 |
|------|------|------|------|
| `deferred10` | R:0,13,9 → CT0+CT13+CT9 | R:**6**,13 → CT6+CT13 | 丢弃 CT9 写（一帧速度滞后可接受） |
| `deferred15` | DB:0456 → CT0+CT4+CT5+CT6 | DB:**6** → CT6 | 丢弃 CT4/CT5 写（debug copy + passthrough） |
| `composite12` | R:0,2 → CT0+CT2 | R:**6**,2 → CT6+CT2 | TAA 在缩放 CT6 运行 |
| `composite23` | DB:06 → CT0+CT6 | DB:**6** → CT6 | 丢弃 CT0 写 |

#### 3. 缓冲缩放

在 `shaders.properties` 中用 `size.buffer.colortexN = scale scale` 缩放：
- **缩放**: CT6..13, CT16..18
- **保持全分辨率**: CT0..5, CT9, CT14, CT15 （gbuffer 输出 + EASU 输出）

#### 4. EASU 升采样 (`composite14`)
- 读 CT6（缩放分辨率）
- 12-tap 边缘自适应升采样
- 写 CT14（全分辨率 RGBA16F，原始 CT14 格式更改）

#### 5. FSR3 深度集成（5 项）

| 特性 | 文件 | 行数 | 说明 |
|------|------|------|------|
| **RectifyHistory** | `lib/SpringFSR/RectifyHistory.glsl` | ~20 | clip 后历史和原始历史按 lock/reactive 混合 |
| **Accumulation Matrix** | `lib/SpringFSR/AccumulationMatrix.glsl` | ~15 | CT2.a 存累积帧数，blend=1/frame |
| **Generate Reactive from Alpha** | `program/composite0.csh` + `lib/SpringFSR/ReactiveMask.glsl` | ~15 | CS 读 colortex0.a 生成 reactive，替代材料 ID 猜测 |
| **Motion Vector Fill** | `program/composite0.csh` | ~30 | CS 膨胀缺失运动向量 |
| **Prev Depth Reconstruct** | `program/composite0.csh` | ~25 | CS 构建前一帧深度缓冲 |

#### 6. UI 调整
```properties
screen.Camera = GAMMA [bloom] [exposure] [simple_filter] [tone_mapping] POST_PROCESS_NOISE [motion_blur] [depth_of_field] [vignette] [letter_box] [SpringFSR]

screen.SpringFSR = SPRINGFSR_MODE <empty> \
                   RCAS_SHARPNESS SPRINGFSR_RCAS RCAS_ENABLE_NOISE_SUPPRESSION SPRINGFSR_RCAS_DENOISE <empty> \
                   SPRINGFSR_DEPTH_CLIP SPRINGFSR_LOCK <empty> \
                   SPRINGFSR_SPHERE_CLIP SPRINGFSR_LUMA_INSTABILITY <empty> \
                   SPRINGFSR_REACTIVE_MASK SPRINGFSR_SHADING_CHANGE
```
所有 SpringFSR/FSR 选项从 `[Antialiasing]` 移至 `[Camera] > [SpringFSR]`。

#### 7. 预设
| 值 | 标签(zh) | 标签(en) | 缩放 | 目标帧率增益 |
|----|---------|---------|------|------------|
| 0 | 关闭 | Off | 1.0x | — |
| 1 | 质量 | Quality | 0.77x | ~30% |
| 2 | 平衡 | Balanced | 0.67x | ~45% |
| 3 | 性能 | Performance | 0.50x | ~60% |
| 4 | 超级性能 | Ultra Performance | 0.33x | ~80% |

### 风险
- Iris only（CS 依赖），OptiFine 不兼容
- CS 桥接可能引入 1 帧延迟（acceptable for upscaling）
- 0.33x Ultra 在低分辨率下画质损失明显，仅推荐高端配置追求极限帧率

### 改动文件
| 文件 | 改动 |
|------|------|
| `program/composite0.csh` | 新建 — CS 桥接 |
| `program/deferred10.glsl` | RENDERTARGETS 0,13,9 → 6,13 |
| `program/deferred15.glsl` | DRAWBUFFERS 0456 → 6 |
| `program/composite12.glsl` | RENDERTARGETS 0,2 → 6,2 |
| `program/composite12.glsl` | 存储 accumulation matrix 到 CT2.a |
| `program/composite23.glsl` | DRAWBUFFERS 06 → 6 |
| `program/composite14.glsl` | 已有 — EASU 升采样 |
| `program/final.glsl` | 读 CT14 取代 CT0 |
| `lib/SpringFSR/RectifyHistory.glsl` | 新建 — clip 后混合 |
| `lib/SpringFSR/AccumulationMatrix.glsl` | 新建 — 帧计数 |
| `lib/SpringFSR/SpringFSR.glsl` | 加新组件 include |
| `lib/settings.glsl` | 加 SPRINGFSR_MODE 4 (Ultra) |
| `shaders.properties` | size.buffer 缩放 + screen.SpringFSR 编排 |
| `shaders/lang/zh_cn.lang` + `en_us.lang` | UI 标签 |


