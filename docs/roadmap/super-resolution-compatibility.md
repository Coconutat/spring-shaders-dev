# Super Resolution Mod 兼容路线图

## B 阶段 ✅（当前 — 最小可行）

**目标**：SR 能识别并正确介入，无 GLSL 侵入式修改。

### 交付物

- [x] `shaders/superresolution.v2.json` — V2 配置，含默认 profile
- [x] `program/final.glsl` — RCAS 条件编译（`!defined(SR_INSTALLED)`）

### B 阶段设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 触发点 | AFTER composite23 | 色调映射后升采样，后期效果（TAA/DOF/Bloom）在低分辨率运行 |
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

### 交付物

- [x] **TAA 抖动适配**：`noise.glsl` 添加 `getJitterNDC()` + 条件编译 `unTAAJitter()`。SR 安装时读 `SRJitterOffset`，否则回退 Halton。
- [x] **顶点着色器替换**：16 个文件（gbuffers_* + dh_*）将 `Halton_2_3[framemod8]` → `getJitterNDC()`
- [x] **启用 `size.buffer` 缩放**：`shaders.properties` 中 colortex0~18 设为 `0.75 0.75`（colortex7 保留 512×512）
- [x] **维度独立 profile**：`superresolution.v2.json` 拆分为 `"0"`（主世界）、`"-1"`（下界）、`"1"`（末地）三个 profile
- [ ] **运动向量预处理评估**：待游戏内验证 — colortex9 缩放后速度精度是否足够
- [ ] **LOD 偏差调整**：待游戏内观察 — 纹理 MIP 是否闪烁

### C 阶段设计决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 缩放比例 | **0.75×** | 性能提升大（~44% 像素减少），画质损失极微 |
| 抖动策略 | **统一入口** | `getJitterNDC()` 封装选择，只改 noise.glsl 一处 |
| 坐标转换 | SRJitterOffset ×2 → NDC | SRJitterOffset [-0.5,0.5] 像素 → [-1,1] NDC 空间 |
| 维度配置 | 三个维度独立 profile，配置相同 | 后续可独立调优 |
| 默认 fallback | `"*"` profile 设为 disabled | 避免未显式启用的维度意外启用 |

### GLSL 改动汇总

| 文件 | 改动 |
|------|------|
| `lib/common/noise.glsl` | 新增 `getJitterNDC()`，`unTAAJitter()` 条件编译 |
| 16 个顶点着色器 | `Halton_2_3[framemod8]` → `getJitterNDC()` |
| `shaders.properties` | `size.buffer` 取消注释 + 0.75× |
| `superresolution.v2.json` | 拆分维度 profile |
| `program/final.glsl` | B 阶段已改：RCAS 条件编译 |

### 验证方式

1. **回退测试**：关闭 SR mod，确认光影行为与 B 阶段前完全一致（无 SR 时回退 Halton + 全分辨率）
2. **功能测试**：开启 SR mod，确认升采样正常工作
3. **维度测试**：在主世界/下界/末地分别验证 SR 是否正确加载
4. **TAA 测试**：观察有无闪烁/鬼影，对比 B 阶段画质
5. **性能测试**：记录 0.75× 缩放下的帧率提升

---

## 未来（探索中）

- **Distant Horizons 兼容**：DH 的 LOD 渲染是否受 SR 缩放影响
- **Voxy 体素兼容**：PATH_TRACING 模式下的 SR 适配
- **HDR mod 兼容**：与 HDR mod 的曝光/色域交互
