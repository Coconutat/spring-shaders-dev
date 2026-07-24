# Super Resolution Mod 兼容路线图

## B 阶段 ✅（当前 — 最小可行）

**目标**：SR 能识别并正确介入，无 GLSL 侵入式修改。

### 交付物

- [x] `shaders/superresolution.v2.json` — V2 配置，含默认 profile
- [x] `program/final.glsl` — RCAS 条件编译（`!defined(SR_INSTALLED)`）

### B 阶段设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 触发点 | AFTER composite21（B 阶段原始设计；E 阶段修正） | 色调映射后升采样会导致 SR 在 gamma 空间工作，改为 bloom 后 HDR 线性空间触发 |
| RCAS 冲突 | 条件编译跳过 | 无 SR 时保留 RCAS，有 SR 时由 SR 锐化 |
| Schema | V2 | 自动 Y 轴翻转，预留 motion_vector_preprocessing |
| 抖动源 | mod | SR 为各算法生成正确抖动 |
| 纹理格式 | RGBA16F | 匹配 colortex0 现有格式，兼容 HDR 管线 |
| 自动曝光 | true | 无需额外 exposure 纹理 |

### 验证方式

1. 安装 Super Resolution Mod 0.8.3-alpha.4+
2. 在光影包设置中启用本光影
3. 检查 SR 是否识别（屏幕上有 SR 状态指示）
4. 切换 FSR1/2/3、DLSS、XeSS 等算法，观察画面是否正确
5. 检查 `colortex0` 输出是否在升采样后正确写回

---

## C 阶段 ✅（已完成 — 深度集成）

**目标**：SR 和光影的 TAA 抖动协同工作，开启 `size.buffer` 缩放，各维度独立配置。

### C 阶段原始设计

- [x] **TAA 抖动适配**：`noise.glsl` 添加 `getJitterNDC()` + 条件编译 `unTAAJitter()`。SR 安装时读 `SRJitterOffset`，否则回退 Halton。
- [x] **顶点着色器替换**：16 个文件（gbuffers_* + dh_*）将 `Halton_2_3[framemod8]` → `getJitterNDC()`
- [x] **启用 `size.buffer` 缩放**：`shaders.properties` 中 colortex0~18 设为 `0.75 0.75`（colortex7 保留 512×512）
- [x] **维度独立 profile**：`superresolution.v2.json` 拆分为 `"0"`（主世界）、`"-1"`（下界）、`"1"`（末地）三个 profile

### C 阶段 Bug 修复 ✅（已完成）

- [x] **`FSR_RCAS` / `RCAS_ENABLE_NOISE_SUPPRESSION` 不在 sliders 列表** → 添加到 sliders
- [x] **`SRJitterOffset` 未声明** → `uniform.glsl` 中 `#ifdef SR_INSTALLED` 块声明
- [x] **`colortex13`/`colortex14` 缺少 `size.buffer`** → 添加
- [x] **`superresolution.v2.json` 结构修正** → inputs/outputs 嵌套到 upscale 下

---

## D 阶段 ✅（已完成 — 深度优化）

**目标**：修复 C 阶段 bug，添加运动向量预处理，完善 SR 配置结构。

### 交付物

- [x] **Bug 修复：`FSR_RCAS`/`RCAS_ENABLE_NOISE_SUPPRESSION` sliders 缺失**
- [x] **Bug 修复：`SRJitterOffset` uniform 未声明** — `uniform.glsl` 中 `#ifdef SR_INSTALLED` 块声明
- [x] **Bug 修复：`colortex13`/`colortex14` 缺少 `size.buffer`**
- [x] **Bug 修复：`superresolution.v2.json` 结构修正** — `inputs`/`outputs` 嵌套到 `upscale` 下
- [x] **运动向量预处理**：`motion_vector_preprocessing_function` 添加运动向量 clamp（max 0.4 UV）
- [ ] **LOD 偏差调整**：待游戏内验证

---

## E 阶段 ✅（本轮 — 架构重构）

**目标**：消除 GLSL 中所有 `#ifdef SR_INSTALLED` 条件编译，通过 `shaders.properties` 变量桥接层统一 SR/非 SR 路径。参考 itRP 的架构设计。

### 决策

| # | 决策 | 变更 | 理由 |
|---|------|------|------|
| 1 | **变量桥接** | `SRJitterOffset` → `springJitterNDC`/`springJitterUV` via `shaders.properties` 条件变量 | 消除 SRJitterOffset 未声明 bug；GLSL 零条件编译 |
| 2 | **动态 size.buffer** | 硬编码 `0.75×` → `SR_RENDER_SCALE_FACTOR`（SR mod 原生宏） | SR 禁用时自动 = 1.0 全分辨率；切换算法自动跟随 |
| 3 | **触发点修正** | `AFTER composite23` → `AFTER composite21` | SR 接收 HDR 线性输入，避免 gamma 空间超分质量损失 |
| 4 | **精确缩放范围** | 排除 colortex7(512²固定)、colortex8(预加载资源)、colortex14(未使用) | 避免对固定/非渲染缓冲误缩放 |
| 5 | **Voxy 抖动同步** | 独立 Halton → `springJitterNDC` | Voxy LOD 与主渲染抖动一致 |
| 6 | **Halton 回退保持** | 非 SR 回退使用精确 `Halton_2_3[framemod8]` 序列（通过 shaders.properties 条件分支模拟） | 向后兼容，SR 关闭时行为完全一致 |

### 交付物

- [x] **变量桥接层**：`shaders.properties` 中 `#if SR_ALGO_SUPPORTS_JITTER == 1` 分支 → `springJitterNDC`/`springJitterUV`
- [x] **GLSL 清理**：`uniform.glsl` 移除 `#ifdef SR_INSTALLED` 块；`noise.glsl` 简化零条件编译
- [x] **动态缩放**：`size.buffer` 使用 `#if SR_SHOULD_APPLY_SCALE == 1` + `SR_RENDER_SCALE_FACTOR`
- [x] **触发点修正**：`superresolution.v2.json` 全部 3 个 profile `composite23` → `composite21`
- [x] **Voxy 兼容**：`voxy.json` uniform `SRJitterOffset` → `springJitterNDC` + `springJitterUV`；`taaOffset` 同步

### 改动汇总

| 文件 | 改动 |
|------|------|
| `shaders/shaders.properties` | +35 行：变量桥接(含 Halton 回退) + 动态 size.buffer |
| `shaders/lib/uniform.glsl` | -7/+2：移除 SR_INSTALLED 块 → springJitterNDC/UV |
| `shaders/lib/common/noise.glsl` | -15/+4：getJitterNDC/unTAAJitter 零条件编译 |
| `shaders/program/voxy.json` | -16/+2：uniform + taaOffset 同步 |
| `shaders/superresolution.v2.json` | -3/+3：触发点 composite23→composite21 |

### 验证方式

1. **回退测试**：关闭 SR mod，确认 Voxy 和主渲染抖动与 C 阶段前一致（Halton 序列不变）
2. **启动测试**：`F3+R` 重载光影，确认无编译报错
3. **错位测试**：SR 开启后观察画面是否有错位（本次用 `SR_RENDER_SCALE_FACTOR` 替代硬编码 0.75）
4. **Voxy 对齐**：Voxy 体素与主渲染是否对齐
5. **算法切换**：切换 FSR1/2/3/XeSS/DLSS，验证 size.buffer 自动跟随

---

## 未来（待定）

- **Distant Horizons 兼容**：DH 的 LOD 渲染是否受 SR 缩放影响
- **HDR mod 兼容**：与 HDR mod 的曝光/色域交互
- **LOD 偏差调整**：纹理 MIP 是否闪烁（待游戏内验证）
- **screenSpaceShadow.glsl**：该文件直接引用 `Halton_2_3[framemod8]` 而非 `getJitterNDC()`——可后续统一
