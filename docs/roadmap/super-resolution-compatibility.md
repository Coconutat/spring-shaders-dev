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

## C 阶段 🚧（规划中 — 深度集成）

**目标**：SR 和光影的 TAA 抖动协同工作，开启 `size.buffer` 缩放，各维度独立配置。

### 待办

- [ ] **TAA 抖动适配**：`composite12.glsl` 中，`#ifdef SR_INSTALLED` 时读 `SRJitterOffset` uniform 替代自有 Halton 序列
- [ ] **启用 `size.buffer` 缩放**：在 `shaders.properties` 取消注释 `size.buffer.colortexN=0.5 0.5`，从半分辨率渲染
- [ ] **维度独立 profile**：为 `world0`（主世界）、`world1`（末地）、`world-1`（下界）分别配置不同的 ups scale 参数
- [ ] **运动向量预处理评估**：检查 SR 是否需要 `motion_vector_preprocessing_function` 来处理半分辨率 velocity
- [ ] **LOD 偏差调整**：启用缩放后确认纹理采样 LOD 偏差正确

### C 阶段设计决策（待定）

这些问题需继续 grilling：

| 问题 | 选项 | 备注 |
|------|------|------|
| 缩放比例 | 0.5 / 0.67 / 0.75 | 取决于性能目标 |
| TAA 与 SR 抖动切换 | 条件编译读 SRJitterOffset | 需确认 `unTAAJitter` 调用点 |
| colortex9 在缩放后的行为 | 需验证半分辨率下运动向量精度 |

### 验证方式

1. 对比 B 阶段画质和性能
2. 确认 TAA 时序积累在缩放后仍稳定（无闪烁/鬼影）
3. 检查各维度配置是否正确加载

---

## 未来（探索中）

- **Distant Horizons 兼容**：DH 的 LOD 渲染是否受 SR 缩放影响
- **Voxy 体素兼容**：PATH_TRACING 模式下的 SR 适配
- **HDR mod 兼容**：与 HDR mod 的曝光/色域交互
