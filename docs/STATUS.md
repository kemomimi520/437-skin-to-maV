# Malody 4.3.7 `.msz` -> Malody V `.msp` 状态报告

更新时间：2026-11-17

## 交付状态（Windows 原生 Key · `free=false`）

- **合规机制**：已启用 `meta.free = false` 原生 Key 转换导出（`native_ui.lua` + 原生 `ProcessorKey` / `NoteLayer` / `JudgeLogicKey` / Replay），旧版 Free 模式导出（`compile_skin` / `compile_preview`）继续保持停用。
- **核心转换与运行时能力**：
  - [converter/msz.py](../converter/msz.py)：支持 `.msz` 全分支（多键数 / PC / Android / 宽高比）合规打包，清理过时阻断并保留明确未映射报错。
  - [converter/native_key.py](../converter/native_key.py) & [converter/assets.py](../converter/assets.py)：
    - 修复部分贴图缺失回退、`size` 负值/纵横比锁定、黑色 LN 头部透明溢色（`_bleed_transparent_rgb`）与 `overlap_image` UV 接缝、轨道无挡板时闲置默认挡板抑制（`syncIdleDefaultCover`）。
    - 转换 `@best` / `@cool` / `@good` 打击音效（`type=5006`）时写入 `ui['hitsounds']`，由 `native_ui.lua` 实时同步 Malody V 的 `key_sound` / `skip_keysound` / `hit_volume` 设置。
    - 按 Malody 4.3.7 `StagePlay` 逻辑还原缺省 `pause` 行为：若 `.mui` 未定义 `pause` 且原皮肤自带 `ui-play-pause.png`（含全透明触控图），生成左上角 `usage=2` 可点击热区并禁用默认按钮；若原皮肤亦无 `ui-play-pause.png`，则保留 MaV 原生默认暂停按钮（`1`）。
  - [converter/gui.py](../converter/gui.py) & `dist/Ma-Skin-Bridge-0.3.0-dev8`：移除过时 `r59` 文案，刷新便携包。

## 最近一次完整验证实证（2026-11-17）

1. **全量单元测试**（`python -m unittest discover -s tests -p "test_*.py"`）：**`Ran 696 tests in 29.015s - OK`**。
2. **实机 `--read-only-install` `ScenePlay` 验证（Windows `Malody V.exe`）**：
   - `PE直轨改.msp` Key 音开关对照：
     - `key_sound=0, hit_volume=80`（`output/probe-pe-final-off`）：`KeySoundBase.zjt=false`，激活分支 `k4_windows_native-sound-best/cool/good` 的实际 `cdm` 音量全部为 **`0.0`**，`native_skin_lua_errors=[]`，`binary_files_unchanged=True`。
     - `key_sound=1`（`output/probe-pe-final-on`）：`KeySoundBase.zjt=true`、`zvs=0.30000001192093`，激活分支 `k4_windows_native-sound-best/cool/good` 实际 `cdm` 音量全部同步为 **`0.30000001192093`**；透明 `ui-play-pause.png` 生成的 `SkinActionPause` 激活于屏幕左上角 `[0, 10] - [100, 110]`（`raycast_target=true`）。
   - `最终版3安卓.msp` & `SHIFTED_6_EXPRESSIVE_HARMONY.msp` 暂停控制与视觉验证：
     - `最终版3安卓`（含全透明 `ui-play-pause.png`）：左上角不可见且 `SkinActionPause` 激活于 `[0, 10] - [100, 110]`（`raycast_target=true`）。
     - `SHIFTED 6`（无 `#pause` 且无 `ui-play-pause.png`）：原生 `WidgetButtonPause` 激活显示于左上角（`active=true`）。

## 保留的未验证边界

- `skin_upload_verified = false`、`normal_score_submission_verified = false`、`full_acceptance = false`：需在线下/线上客户端实测皮肤上传及正常联网游玩成绩上传。
- Android 实机端到端验证暂未执行。
