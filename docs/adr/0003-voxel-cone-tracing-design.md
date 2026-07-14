# ADR-0003: Voxy 体素锥追踪系统设计

**状态**: 已采纳  
**日期**: 2024  
**作者**: 中影 / ZYPanDa

## 背景

为了实现路径追踪全局光照和彩色光源扩散，需要将世界几何体素化到 3D 纹理中，以便在 deferred 阶段进行体素锥追踪采样。

## 决策

### 体素分辨率

- **尺寸**: 256×128×256（X×Y×Z）
- **范围**: 以玩家为中心 ±128 块（水平），±64 块（垂直）
- **体素大小**: 每个体素 = 1 个 Minecraft 方块

### 纹理分配

| 纹理 | 用途 | 格式 | 逐帧清除 |
|------|------|------|----------|
| `customimg0` (voxel) | 体素颜色 + 亮度 | RGBA8 | 是 |
| `customimg4` (voxelLitSky) | 体素光照天空可见度 | RGBA8 | 是 |
| `customimg5` (voxelPrev) | 前一帧体素颜色 | RGBA8 | 否 |
| `customimg6` (voxelLitSkyPrev) | 前一帧体素光照 | RGBA8 | 否 |
| `customimg1` (tmpX) | 临时存储 X 轴 | R16UI | 是 (仅 PT) |
| `customimg2` (tmpY) | 临时存储 Y 轴 | R16UI | 是 (仅 PT) |
| `customimg3` (SDF) | 有符号距离场 | R16UI | 是 (仅 PT) |

### 条件启用

- `PATH_TRACING || COLORED_LIGHT` 时：创建 `customimg0/4/5/6`
- `PATH_TRACING` 时：额外创建 `customimg1/2/3` (tmpX/tmpY/SDF)
- 需要同步启用 `begin`、`shadowcomp*`、`deferred6/7/8`

### 维度限制

- Voxy 入口仅主世界存在（`world0/voxy_opaque.glsl`、`world0/voxy_translucent.glsl`）
- 末地/下界仅有 `voxy.json` 配置（`opaquePatchData` 和 `translucentPatchData` 均为 `discard`，即空操作）
- `NO_VOXEL` ID (20) 的方块不参与体素化

## 权衡

| 选项 | 优点 | 缺点 |
|------|------|------|
| **256×128×256 固定分辨率 (选定)** | 每体素对应一个方块，实现简单 | 远处细节丢失；大范围超出体素空间 |
| **动态分辨率/层级** | 远处可用更低分辨率覆盖更大范围 | 实现复杂度大幅增加；GLSL 限制多 |
| **屏幕空间追踪替代** | 无需体素化，性能好 | 仅能反射/遮蔽屏幕内物体 |

## 影响

- `VOXY` 宏会改变部分 pass 的 RENDERTARGETS 数量与写入布局。
- `deferred21` 仅在 `VOXY` 下启用。
- 修改体素分辨率需要同步更新 `uniform.glsl`、`settings.glsl`、`shaders.properties` 中的 `image.*` 声明。
