# ADR-0002: GBuffer 布局与 GBF 采样切换

**状态**: 已采纳  
**日期**: 2024 (项目初始)  
**作者**: 中影 / ZYPanDa

## 背景

OptiFine/Iris 的 GBuffer Pass (`gbuffers_*`) 写入 `colortex0..7`，而 Deferred/Composite Pass 同样需要读取这些缓冲。但 deferred 阶段有时希望写入同一缓冲的不同语义数据，且各 pass 的 RENDERTARGETS 声明不同。

## 决策

### GBuffer 通道分配

分配 `colortex0..18` 共 19 个缓冲，每个有固定的格式和语义（详见 `program/composite.glsl` 顶部的注释块和 `CONTEXT.md` 的 GBuffer 缓冲布局表）。

### GBF 宏切换

定义 `GBF` 宏时，`uniform.glsl` 将 `colortex4..7` 的采样器别名切换为 `gaux1..4`。未定义 `GBF` 时使用原始名称 `colortex4..7`。

### 3D 纹理路由

定义 `CLOUD3D / SKY_BOX / SHD / PROGRAM_VLF` 宏时，`colortex2` 和 `colortex8` 声明为 `sampler3D`（绑定 3D 噪声纹理），否则为 `sampler2D`。

## 权衡

| 选项 | 优点 | 缺点 |
|------|------|------|
| **固定布局 + GBF 宏 (选定)** | 缓冲语义明确；GBF 自动切换采样源，避免改代码；统一查找表 | 缓冲数量有限（colortex0..18）；改变布局会级联破坏所有 pass；GBF 漏定义会"能编译但读错缓冲" |
| **动态渲染目标** | 灵活分配 | Iris/OptiFine 不支持；需要运行时重配 |
| **全部分散独立缓冲** | 无别名冲突 | 缓冲数量耗尽快；内存占用高 |

## 影响

- 修改任一 CT4/CT5 字段会级联破坏光照链路。
- GBuffer 编解码必须走 `lib/common/utils.glsl` 的 `pack/unpack` 函数。
- 新增 pass 时需确认 `RENDERTARGETS` 声明和 `colortexFormat` 声明一致。
- `colortex9` 向上编号的缓冲（9-18）仅在特定 pass 中写入（如 deferred、composite、voxy）。
