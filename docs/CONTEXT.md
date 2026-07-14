# 春 v2 (Spring Shaders v2) — 领域词表

> Minecraft OptiFine/Iris 光影包。GLSL 4.50 compatibility。
> 作者：中影 / ZYPanDa
> 许可证：CC BY-NC-SA 4.0

---

## 核心概念

### 渲染管线 (Rendering Pipeline)

| 术语 | 定义 |
|------|------|
| **GBuffer Pass** | 几何缓冲区阶段。将场景几何信息（颜色、法线、深度、材质ID等）写入多个 color attachments (`colortex0..18`)。由 `gbuffers_*` 系列 program 组成。 |
| **Shadow Pass** | 阴影贴图生成阶段。从光源视角渲染深度/颜色到 `shadowtex0/1` 和 `shadowcolor0/1`。 |
| **Deferred Pass** | 延迟光照阶段。读取 GBuffer 数据进行光照计算：阴影、RSM、SSAO、SSR、路径追踪等。由 `deferred*` 系列 program 组成。 |
| **Composite Pass** | 合成阶段。在延迟光照后进行后处理：Bloom、TAA、色调映射、运动模糊、景深等。由 `composite*` 系列 program 组成。 |
| **Final Pass** | 最终输出阶段。将渲染结果写入屏幕。 |
| **Shadow Composite** | 阴影合成阶段。`shadowcomp*` 系列，用于路径追踪/彩色光源的阴影信息预处理。 |
| **Begin Pass** | 初始化阶段。`begin.csh` 计算着色器，用于路径追踪/彩色光源下的体素化初始化。 |

### 维度路由 (Dimension Routing)

| 术语 | 定义 |
|------|------|
| **world0/** | 主世界入口包装层。`#include` 指向 `/program/*.glsl`。包含完整渲染管线。 |
| **world1/** | 末地入口包装层。`#include` 指向 `/program/world_1/*.glsl`。缺少 `deferred5/21`，另有 `deferred9`。 |
| **world-1/** | 下界入口包装层。`#include` 指向 `/program/world__1/*.glsl`（双下划线）。缺少 `deferred4/5/21`。 |
| **维度宏** | `NETHER`（下界）、`END`（末地）——包装文件中 `#define`，被 program 内代码条件判断。 |

### 双层架构 (Two-Layer Architecture)

| 术语 | 定义 |
|------|------|
| **包装层 (Wrapper)** | `shaders/world*/*.fsh|.vsh|.csh|.gsh`——仅注入维度/阶段宏并 `#include` 路由到 program。 |
| **实现层 (Implementation)** | `shaders/program/*.glsl` + `shaders/lib/*`——功能实现主体，不关心维度差异。 |

### GBuffer 缓冲布局 (Buffer Layout)

| 缓冲 | 格式 | 内容 |
|------|------|------|
| **colortex0** | RGBA16F | 场景颜色 (HDR) |
| **colortex1** | RGBA16F | HRR (历史重用资源) 数据 |
| **colortex2** | RGBA16F | TAA 颜色 / 3D 噪声纹理 (条件 3D) |
| **colortex3** | RGBA16F | HRR 时序数据 (RSM/AO/云/SSR/雾) |
| **colortex4** | RGBA16 | `r`: 视差阴影/AO, `g`: blockID/gbufferID, `ba`: specular (packed) |
| **colortex5** | RGBA16F | `rg`: 法线 (编码), `ba`: 光照贴图坐标 |
| **colortex6** | RG32F | HRR 法线/深度 (前一帧/当前帧) |
| **colortex7** | RGBA16F | 天空盒 / T1 / MS / 太阳颜色 / 天空颜色 / 手部颜色 |
| **colortex8** | RGBA16F | 自定义纹理 (MS/Noise3D low) / 3D 噪声 (条件) |
| **colortex9** | RGBA16F | `rg`: 速度, `ba`: N |
| **colortex10** | RGBA16F | 路径追踪时序数据 |
| **colortex11** | RGBA16F | 路径追踪滤波数据 |
| **colortex12** | R32F | (预留) |
| **colortex13** | RGBA16 | (预留) |
| **colortex15** | RGBA8 | (预留) |
| **colortex16** | RGBA8 | Voxy 不透明 |
| **colortex17** | RGBA16 | Voxy 半透明 |
| **colortex18** | RGBA16F | Voxy (预留) |

### GBuffer 采样切换 (GBF 宏)

| 术语 | 定义 |
|------|------|
| **GBF** | GBuffer Pass 宏。定义时 `uniform` 将 `colortex4..7` 别名为 `gaux1..4`。未定义时使用 `colortex4..7`。 |
| **CLOUD3D / SKY_BOX / SHD / PROGRAM_VLF** | 3D 纹理路由宏。定义时 `colortex2` 和 `colortex8` 为 `sampler3D`，否则为 `sampler2D`。 |

---

## 材质与 ID 系统

### 材质 ID (Material ID)

材质通过 `block.properties` 的数字 ID → `materialIdMapper.glsl` 映射 → `settings.glsl` 常量 → CT4 打包的链路传输。

| ID | 常量 | 含义 |
|----|------|------|
| 1.0 | `PLANTS_SHORT` | 短植物（只有顶部顶点摇晃） |
| 2.0 | `PLANTS_TALL_L` | 高植物下半部分 |
| 3.0 | `PLANTS_TALL_U` | 高植物上半部分 |
| 4.0 | `LEAVES` | 树叶（全顶点摇晃） |
| 5.0 | `PLANTS_OTHER` | 其他植物/片状物（不摇晃，生成软阴影） |
| 11.0 | `WATER` | 水 |
| 12.0 | `ICE` | 冰 |
| 21.0 | `GLOWING_BLOCK` | 发光方块 |
| 31.0 | `NO_ANISO` | 不参与各向异性过滤（强制跳过，防伪影） |
| 32.0 | `NO_VOXEL` | 不参与体素化 |
| 33.0 | `USE_ART_COL` | 体素化时使用人造光源颜色 |
| 51.0 | `ENTITIES` | 实体 |
| 52.0 | `LIGHTNING_BOLT` | 闪电 |
| 53.0 | `FIREWORK_ROCKET` | 烟花火箭 |
| 61.0 | `BLOCK` | 方块（hand/block 通用） |
| 71.0 | `HAND` | 手部 |
| 101.0 | `DH_TERRAIN` | Distant Horizons 地形 |
| 102.0 | `DH_LEAVES` | DH 树叶 |
| 103.0 | `DH_WOOD` | DH 木头 |

### 方块 ID 映射 (block.properties)

| 数字 ID | 用途 | 代表方块 |
|---------|------|---------|
| 31 | 短植物摇晃 | `short_grass`, `dandelion`, `wheat`, `fern` 等 |
| 10175 | 高植物下半 | `tall_grass:lower`, `sunflower:lower` 等 |
| 11175 | 高植物上半 | `tall_grass:upper`, `sunflower:upper` 等 |
| 10176 | 不摇晃植物 | `bamboo`, `sapling`, `cobweb`, `sugar_cane` 等 |
| 18 | 树叶 | `oak_leaves`, `vine`, `azalea_leaves` 等 |
| 79 | 冰 | `ice` |
| 8 | 水 | `flowing_water`, `water` |
| 95 | 染色玻璃 | `tinted_glass`, `pink_stained_glass` |
| 20 | 玻璃/链条 | `glass`, `glass_pane`, `iron_chain` |
| 61 | 人造光源色 | `furnace` |
| 89 | 发光方块 | `glowstone`, `jack_o_lantern`, `lava`, `beacon`, `torch` 等 |
| 10 | 不各向异性 | `flowing_lava`, `lava` |

---

## 渲染功能模块

### 光照 (Lighting)

| 术语 | 定义 |
|------|------|
| **直接光照 (Direct Light)** | 来自太阳/月亮的阴影投射光照。通过 `shadowMapping.glsl` 实现 PCF/PCSS 软阴影。 |
| **间接光照 (Indirect Light)** | RSM（反射阴影映射）实现的一次间接漫反射光照。 |
| **SSAO / GTAO** | 屏幕空间环境光遮蔽。支持 SSAO 和 GTAO 两种模式，带多重弹射模拟。 |
| **路径追踪 (Path Tracing)** | 试验性体素锥追踪漫反射全局光照。需要 `PATH_TRACING` 宏。 |
| **彩色光源 (Colored Light)** | 使用体素化实现方块颜色光照传播。与路径追踪互斥（不能同时开启）。 |
| **天空光 (Sky Light)** | 原版天际光 + 自定义入射光颜色调节。 |
| **人工光 (Artificial Light)** | 原版方块光源 + 手持动态光源，带法线影响。 |
| **漏光修复 (Leakage Repair)** | 使用原版天光遮蔽来修复 RSM/路径追踪的漏光问题。可通过 `DISABLE_LEAKAGE_REPAIR` 关闭。 |

### 天空与大气 (Sky & Atmosphere)

| 术语 | 定义 |
|------|------|
| **大气散射 (Atmospheric Scattering)** | Precomputed Atmospheric Scattering。基于 Rayleigh + Mie + Ozone 物理模型。参考 Games202 课程。 |
| **体积雾 (Volumetric Fog)** | 基于物理的雾效，含散射/吸收系数，按日照时间段控制覆盖率。 |
| **体积云 (Volumetric Clouds)** | 3D 噪波驱动的体积云渲染，含多重散射模拟（银边/内散射粉末效应）、云隙光（Crepuscular Light）。 |
| **2D 云 (Clouds 2D)** | 轻量级 2D 纹理云层，作为体积云的备选或补充。 |
| **云影 (Cloud Shadow)** | 体积云投射到地面的阴影，遮挡阳光。 |
| **天体 (Celestial)** | 太阳、月亮、星辰渲染。太阳带 Mie 散射光晕。 |

### 水 (Water)

| 术语 | 定义 |
|------|------|
| **波浪 (Wave)** | 三种波浪模式：类型 0/1/2。含视差映射波浪和法线迭代。 |
| **水面反射 (Water Reflection)** | 屏幕空间光线步进反射（SSR），含菲涅尔效应和 F0 控制。 |
| **水面折射 (Water Refraction)** | 基于 IOR 的折射扭曲效果。 |
| **焦散 (Caustics)** | 水底焦散光照效果，含色散。 |
| **水下雾 (Underwater Fog)** | 水下体积雾，含光照衰减和对比度调整。 |
| **半透明光照 (Translucent Lighting)** | 半透明材质（冰、染色玻璃等）的光照处理，含阴影和 PBR。 |

### 材质 (Material)

| 术语 | 定义 |
|------|------|
| **PBR 反射 (PBR Reflectivity)** | 基于 PBR 材质的屏幕空间反射，含粗糙度/金属度/F0。支持方向采样和模糊。 |
| **视差映射 (Parallax Mapping)** | 视差遮蔽映射 (POM) / 陡峭视差映射，含自阴影。 |
| **SSS (Subsurface Scattering)** | 次表面散射模拟。 |
| **各向异性过滤 (Anisotropic Filtering)** | 自定义各向异性过滤，两种模式：基于法线/基于渐变。 |
| **雨天湿地 (Rainy Ground Wet)** | 雨天时地面变湿效果：提高光滑度和 F0，产生涟漪法线扰动。 |

### 后处理 (Post-Processing)

| 术语 | 定义 |
|------|------|
| **TAA (Temporal Anti-Aliasing)** | 时序抗锯齿。Halton 序列抖动 + 历史帧混合 + 方差裁剪 + 深度置信度。 |
| **FSR RCAS** | AMD FidelityFX 锐化，含噪声抑制。 |
| **Bloom** | 泛光效果，分多层叠加。按天气/维度/时段调节强度。 |
| **色调映射 (Tone Mapping)** | 支持 AgX、ACESFull、Hejl、Hable (Uncharted2) 等多种映射。 |
| **曝光 (Exposure)** | 自动曝光/手动曝光，目标亮度调节。 |
| **运动模糊 (Motion Blur)** | 基于速度向量的运动模糊。 |
| **景深 (Depth of Field)** | Bokeh 景深效果。 |
| **暗角 (Vignette)** | 屏幕四角暗化。 |
| **信箱 (Letter Box)** | 电影宽银幕黑边。 |
| **颜色滤镜 (Simple Filter)** | 斜率 (RGB 独立)、对比度、饱和度、白点调节。 |
| **Profile** | 预设配置：Balanced(AgX/ACES)、Comfortable、Vivid、Bright、Native。 |

### 顶点 (Vertex)

| 术语 | 定义 |
|------|------|
| **摇曳动画 (Waving Plants)** | 植物/树叶的顶点动画，基于噪声和时间。短植物只动上部顶点。 |

---

## 特殊技术

| 术语 | 定义 |
|------|------|
| **Voxy (体素化)** | 体素锥追踪系统。将世界几何体素化到 256×128×256 3D 纹理，用于路径追踪/彩色光源。仅主世界有 GLSL 入口。 |
| **Distant Horizons (DH)** | 远距离渲染 LOD 系统兼容。`dh_terrain`、`dh_water`、`dh_shadow` 仅在主世界存在。 |
| **HRR (History Reuse Resources)** | 时序重用资源机制。跨帧复用的数据（RSM/AO/云/SSR/雾）在 `colortex1/3/6` 中，用于时序滤波和降噪。 |
| **RSM (Reflective Shadow Maps)** | 反射阴影映射。从光源视角存储世界像素位置/法线/通量，用于一次间接光照。 |
| **PCSS (Percentage Closer Soft Shadows)** | 百分比渐近软阴影。使用 Blocker Search 确定半影大小。 |
| **T1 纹理 (Transmittance 1D)** | 一维查找表，预计算大气透射率。 |
| **MS 纹理 (Multi-Scattering)** | 64×64 纹理，预计算大气多次散射。 |
| **Noise3D** | 3D 噪声纹理（低分辨率 128×128×128，高分辨率 64×64×64），用于体积云和大气采样。 |

---

## 编译与测试

| 术语 | 定义 |
|------|------|
| **F3+R** | 游戏内重载光影快捷键，唯一验证方式。 |
| **shaders.properties** | 光影配置文件。定义程序启停条件、缓冲区格式、混合模式、纹理绑定、UI 布局。 |
| **alphaTest** | 透明测试阈值。terrain/water/entities=0.005，shadow=0.01。 |
