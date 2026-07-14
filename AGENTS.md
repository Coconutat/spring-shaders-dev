# AGENTS.md

Minecraft OptiFine/Iris 光影包（GLSL 4.50 compatibility）。无 npm/gradle/cmake 等构建系统。

## 测试

- 无 CLI 测试。唯一验证方式：游戏内 F3+R 重载光影观察编译结果。
- 排错时在 `shaders.properties` 临时只启用单个 `program.world*/xxx.enabled` 做最小化复现。
- 快速冒烟：改 `shaders/program/*.glsl` 后重载；`shaders/world*/*` 只是入口包装层。

## 渲染管线（按执行顺序）

```
GBuffer Pass (gbuffers_*) → Shadow Pass (shadow) → Deferred Pass (deferred*) → Composite Pass (composite*) → Final Pass (final)
                                                                        ↕
                                                              Shadow Composite (shadowcomp*)   ← PATH_TRACING || COLORED_LIGHT
                                                                        ↕
                                                              Begin Pass (begin.csh)            ← PATH_TRACING || COLORED_LIGHT
                                                                        ↕
                                                              Voxy Pass (voxy_*)                ← VOXY
```

### GBuffer 缓冲分配（colortex0..18）

| 缓冲 | 格式 | 内容 |
|------|------|------|
| CT0 | RGBA16F | 场景颜色 (HDR) |
| CT1 | RGBA16F | HRR 数据 |
| CT2 | RGBA16F | TAA 颜色 / 3D噪声(条件) |
| CT3 | RGBA16F | HRR 时序 (RSM/AO/云/SSR/雾) |
| CT4 | RGBA16 | r:视差阴影/AO, g:blockID/gbufferID, ba:specular |
| CT5 | RGBA16F | rg:法线(编码), ba:光照贴图坐标 |
| CT6 | RG32F | HRR 法线/深度(前/当前帧) |
| CT7 | RGBA16F | 天空盒/T1/MS/太阳色/天空色 |
| CT8 | RGBA16F | 自定义纹理 / 3D噪声(条件) |
| CT9 | RGBA16F | rg:速度, ba:N |
| CT10 | RGBA16F | 路径追踪时序 |
| CT11 | RGBA16F | 路径追踪滤波 |
| CT12 | R32F | (预留) |
| CT13 | RGBA16 | (预留) |
| CT15 | RGBA8 | (预留) |
| CT16 | RGBA8 | Voxy 不透明 |
| CT17 | RGBA16 | Voxy 半透明 |
| CT18 | RGBA16F | Voxy (预留) |

### 各维度 Deferred Pass 差异

| Pass | world0 | world1 (末地) | world-1 (下界) |
|------|--------|---------------|-----------------|
| deferred4 | ✔ | ✔ | ✗ |
| deferred5 | ✔ | ✔ | ✗ |
| deferred9 | ✗ | ✔ | ✗ |
| deferred21 | ✔(仅VOXY) | ✔(仅VOXY) | ✗ |

## 架构

### 双层架构：包装层 + 实现层

- `shaders/world*/*.fsh|vsh|csh|gsh` — 仅注入维度/阶段宏并 `#include` 路由到 program。
- `shaders/program/*.glsl` + `shaders/lib/*` — 功能实现主体。

### 维度路由（硬编码分片）

| 包装目录 | include 目标 | 说明 |
|----------|-------------|------|
| `world0/` | `/program/*` | 主世界 |
| `world1/` | `/program/world_1/*` | 末地 |
| `world-1/` | `/program/world__1/*` | 下界（双下划线） |

- 跨维共享改动通常需要三处对齐。
- Deferred pass 按维度分化：并非所有维度都有相同的 deferred 文件集（如 world__1 缺少 deferred5/21，world_1 另有 deferred9）。

### 包装文件编写规则

```glsl
#version 450 compatibility
#define FSH        // 或 VSH / GSH / CSH
#define GBF        // 如为 GBuffer pass，必须有
#define NETHER     // 或 END（按维度需要）
#include "/program/some_program.glsl"
```

- 必须先 `#define` 阶段宏再 `#include`；漏定义会走错代码分支。
- **`GBF` 是 GBuffer pass 强制要求**：`uniform.glsl` 依赖 `GBF` 将纹理别名切到 `gaux1..4`，否则回退到 `colortex4..7`，结果"能编译但读错缓冲"。

### sampler 维度路由器

- **`CLOUD3D` / `SKY_BOX` / `SHD` / `PROGRAM_VLF`**：定义时 `colortex2` 和 `colortex8` 为 `sampler3D`，未定义时为 `sampler2D`。同一段采样代码复用前必须确认 pass 宏。
- **`GBF`**：切换 GBuffer 采样源 `gaux1..4` ↔ `colortex4..7`。

### Path Tracing / Colored Light 联合开关

启用 `PATH_TRACING` 或 `COLORED_LIGHT` 时，以下 program 必须**同步启用**，否则依赖缓冲缺失：
- `begin`
- `shadowcomp_a/b/c`、`shadowcomp`、`shadowcomp1_a/b`
- `deferred6`、`deferred7`、`deferred8`

### Voxy 体素链路

- Voxy 入口仅主世界存在（`world0/voxy_opaque.glsl`、`world0/voxy_translucent.glsl`）。
- 末地/下界仅有 `voxy.json` 配置文件，无实际 GLSL 入口。
- `VOXY` 宏会改变部分 pass 的 RENDERTARGETS 数量与写入布局。

### Distant Horizons

- `dh_*` 包装文件（`dh_terrain`、`dh_water`、`dh_shadow`）仅在 `world0/` 存在，末地/下界无 DH 入口。

## lib/ 目录模块组织

```
lib/
├── settings.glsl          # 全部用户可调参数（#define），带 slider 注释
├── uniform.glsl            # 全部 OpenGL uniform 声明（sampler/matrix/vector）
├── wavingPlants.glsl       # 植物/树叶顶点摇曳动画
├── antialiasing/           # 各向异性过滤实现
│   └── anisotropicFiltering.glsl
├── atmosphere/             # 大气散射/体积云/体积雾/天体
├── camera/                 # 颜色工具链（colorToolkit）、滤镜（filter）
├── common/                 # 通用工具函数
│   ├── utils.glsl          # pack/unpack、数学工具、lerp、编码解码
│   ├── gbufferData.glsl    # GBuffer 解码（CT4/CT5 字段提取）
│   ├── materialIdMapper.glsl # block.properties ID → 材质常量映射
│   ├── noise.glsl          # Bayer 序列、Halton 序列、TAA 反抖动
│   ├── normal.glsl         # 法线编码解码（八面体映射）
│   ├── octahedralMapping.glsl # 八面体映射工具
│   └── position.glsl       # 屏幕/视图/世界空间坐标转换
├── lighting/               # 光照计算
│   ├── lightmap.glsl       # 原版光照贴图解码
│   ├── pathTracing.glsl    # 体素锥追踪路径追踪
│   ├── rayTracing.glsl     # 屏幕空间光线步进(SSR)
│   ├── RSM.glsl            # 反射阴影映射
│   ├── screenSpaceShadow.glsl # 屏幕空间阴影
│   ├── shadowMapping.glsl  # 阴影映射（PCF/PCSS/VSM）
│   ├── SSAO.glsl           # 屏幕空间环境光遮蔽(GTAO/SSAO)
│   └── voxelization.glsl   # 体素化
├── surface/                # 表面效果（视差映射、涟漪、PBR）
└── water/                  # 水面渲染
```

### 方块 ID 硬耦合链路

`block.properties` 数字 ID → `materialIdMapper.glsl` 映射 → `settings.glsl` 常量 → CT4 打包（`ID_SCALE=255`）

修改任一环节需四处同步。
- **`block id 10` → `NO_ANISO`**：在 `gbuffers_terrain` 强制跳过各向异性过滤，不是可选优化而是防伪影约束，不可删除。

## Deferred Pass 链（光照计算顺序）

deferred 系列 pass 按编号顺序执行，每个 pass 负责特定的光照计算：

| Pass | 功能 | 说明 |
|------|------|------|
| deferred | HRR 法线/深度重建 | 从 depthtex 重建世界空间法线和深度，写入 CT6 |
| deferred1 | 同上（depthtex1） | 处理半透明/水面的法线深度 |
| deferred2 | RSM 间接光照 | 反射阴影映射采样 + 降噪，写入 CT3 |
| deferred3 | SSAO/GTAO | 环境光遮蔽计算，写入 CT4.r |
| deferred4 | 阴影混合 + 光照累积 | 直接光照 + 间接光照 + AO 合并，写入 CT0 |
| deferred5 | 水面半透明光照 | 半透明材质特殊光照处理 |
| deferred6 | 体素化 opaque | 写入体素纹理 (PT/CL 专用) |
| deferred7 | 体素化 translucent | 半透明体素写入 (PT/CL 专用) |
| deferred8 | 体素 SDF 构建 | 有符号距离场构建 (PT/CL 专用) |
| deferred10 | 无光照基础色 | 屏幕空间无光照颜色（用于路径追踪/调试） |
| deferred11 | 水下雾 | 水下体积雾计算 |
| deferred12 | 路径追踪时序 | 路径追踪采样累积，写入 CT10 |
| deferred13/14 | PBR 反射模糊 | PBR 反射方向模糊 (条件启用) |
| deferred15 | PBR 反射合成 | PBR 反射合成到 CT0 |
| deferred21 | Voxy 光照注入 | 体素光照写回屏幕空间 (仅 VOXY) |

## 核心功能矩阵

| 功能 | 宏开关 | 依赖 Pass | 备注 |
|------|--------|-----------|------|
| 大气散射 | `ATMOSPHERE_SCATTERING_FOG` | composite | 预计算大气散射 + 雾混合 |
| 体积云 | `VOLUMETRIC_CLOUDS` | composite | 3D 噪波驱动的体积云，带云影 |
| 2D 云 | `CLOUDS_2D` | composite | 轻量替代方案 |
| 体积雾 | `VOLUMETRIC_FOG` | composite/deferred | 根据时段调节覆盖率 |
| 云隙光 | `CREPUSCULAR_LIGHT` | composite | 屏幕空间体积光遮蔽 |
| 水渲染 | — | gbuffers_water | 波浪/反射/折射/焦散 |
| RSM | `RSM_ENABLED` | deferred2/3/4 | 一次间接漫反射 |
| SSAO/GTAO | `AO_ENABLED` | deferred3 | 环境光遮蔽 |
| 路径追踪 | `PATH_TRACING` | deferred6/7/8/12 | 体素锥追踪 GI |
| 彩色光源 | `COLORED_LIGHT` | deferred6/7/8 | 方块颜色光照传播 |
| PBR 反射 | `PBR_REFLECTIVITY` | deferred13/14/15 | 屏幕空间 PBR 反射 |
| 视差映射 | `PARALLAX_MAPPING` | gbuffers_terrain | POM/陡峭视差 |
| TAA | — | composite | Halton 抖动 + 历史帧混合 |
| 色调映射 | `TONE_MAPPING` | composite | AgX/ACES/Hejl/Hable |
| Bloom | `BLOOM` | composite | 分层泛光 |
| 运动模糊 | `MOTION_BLUR` | final | 速度向量驱动 |
| 景深 | `DEPTH_OF_FIELD` | final | Bokeh DOF |

## 约定

### Include 顺序（隐式约束）

先 `uniform` → `settings` → `utils`，再 `common`，最后功能模块。调换顺序容易触发宏/类型未定义。

### settings.glsl 参数开关

参数集中在 `lib/settings.glsl` 的 `#define`，必须保持 `// [value1 value2 ...]` slider 注释格式——会被 `shaders.properties` UI 读取。改参数需确认 `screen.*` 和 `sliders` 编排也包含该参数名。

### GBuffer 编解码

必须走 `lib/common/utils.glsl` 的 `pack/unpack` 函数，并保持 `lib/common/gbufferData.glsl` 的通道语义不变。`CT4/CT5` 字段被多个 deferred pass 复用，改任一字段会级联破坏光照链路。

### alphaTest 阈值

与 `shaders.properties` 的 `alphaTest.*` 保持同步：terrain/water/entities=0.005，shadow=0.01。

### `customimg*` 资源

- `customimg0/4/5/6`（voxel/voxelLitSky/voxelPrev/voxelLitSkyPrev）在 `PATH_TRACING || COLORED_LIGHT` 下创建。
- `customimg1/2/3`（tmpX/tmpY/SDF）仅在 `PATH_TRACING` 下创建。
- 扩展资源分配必须先保证 `shaders.properties` 声明与宏条件一致。

### 死代码

仓库内 `* copy.glsl` 文件（如 `fog copy.glsl`、`parallaxMapping copy.glsl` 等）是备份/草稿，不在当前 include 链中，不应引用或修改。
