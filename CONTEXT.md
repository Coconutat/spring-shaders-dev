# 领域模型

## Super Resolution Mod 兼容性

### 核心概念

- **Super Resolution Mod (SR)**：Minecraft 模组，集成 FSR1/2/3、DLSS、XeSS、NIS 等超分辨率算法，降低内部渲染分辨率后重建画面以提升帧率。
- **升采样 (Upscale)**：将低分辨率渲染结果重建为高分辨率输出的过程。SR 在指定的 composite pass 触发点介入。
- **抖动 (Jitter)**：每帧亚像素偏移，使时域超分算法能采集多帧信息重建细节。来源可以是 `mod`（SR 生成）或 `shaderpack`（光影自管）。

### 接口契约

- **`superresolution.v2.json`**：光影包根目录的配置文件，声明触发点、输入/输出纹理、抖动源、HDR/曝光设置。SR 以降序尝试 `v4`→`v3`→`v2`→`v1`→无后缀。
- **触发点 (Trigger)**：`BEFORE` 或 `AFTER` 某个 composite pass。本光影选 `AFTER composite23`。
- **输入纹理**：`color`（colortex0）、`depth`（depthtex）、`motion_vectors`（colortex9）。所有输入均为渲染分辨率。
- **输出纹理**：`upscaled_color` 写回 colortex0，区域为屏幕分辨率（`-2`）。
- **运动向量规范**：UV 空间（归一化 -1 到 1），公式 `current_uv - previous_uv`，**不**翻转 Y 轴，**不**转换为 NDC。

### 注入的资源

- **宏 (Macros)**：SR 注入 `SR_INSTALLED`、`SR_ENABLE`/`SR_DISABLE`、`SR_USING_ALGO`、`SR_SCALED_WIDTH/HEIGHT`、`SR_SCREEN_WIDTH/HEIGHT`、`SR_JITTER_SEQUENCE_LENGTH` 等。
- **Uniforms**：`SRJitterOffset`（vec2，像素空间）、`SRRenderScale`（float）、`SRRatio`（float）等。

### 维度

- 下界（`world-1`/`world__1`）和末地（`world1`/`world_1`）共享同一套 SR 配置（通配符 `*`），C 阶段可独立调优。

### 相关文件

- `shaders/superresolution.v2.json` — SR 兼容配置
- `shaders/program/final.glsl` — 条件编译 RCAS 避免双重锐化

## 管线阶段

| 阶段 | 说明 |
|------|------|
| GBuffer | 几何缓冲写入（colortex0/4/5/9/15） |
| Composite (composite~composite24) | 延迟光照、半分辨率雾、TAA、DOF、泛光、色调映射 |
| **SR 触发点** = composite23 之后 | 色调映射后的 HDR 颜色被 SR 升采样 |
| Final | sRGB 编码 + 信箱遮罩 → 屏幕输出 |

## C 阶段改动

### 统一抖动入口

- `getJitterNDC()` 封装顶点抖动选择（`noise.glsl`）：SR 安装时读 `SRJitterOffset`（像素空间 → NDC），否则回退 Halton 序列。
- `unTAAJitter()` 条件编译：SR 路径下直接使用 `SRJitterOffset`（无需 `*0.5` 缩放到像素级），Halton 路径保留原有 `*0.5`。
- 16 个顶点着色器将 `Halton_2_3[framemod8]` 替换为 `getJitterNDC()`。

### 渲染缩放

- `shaders.properties` 启用 `size.buffer.colortexN=0.75 0.75`（colortex0~18，colortex7=512×512 除外）。
- 所有渲染 pass 在 75% 分辨率下运行，SR 在 composite23 后升采样回屏幕分辨率。

### 维度配置

- `superresolution.v2.json` 拆分为 `"0"`（主世界）、`"-1"`（下界）、`"1"`（末地）三个独立 profile。
- `"*"` 默认 profile 设为禁用，各维度需显式启用。
