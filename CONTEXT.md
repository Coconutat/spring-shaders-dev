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
