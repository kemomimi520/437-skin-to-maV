# 437-skin-to-maV (`Ma Skin Bridge`)

Malody 4.3.7 `.msz` → Malody V 原生 Key (`.msp`, `free=false`) 皮肤转换工具。  
Convert legacy **Malody 4.3.7** Key-mode skins (`.msz`) into **Malody V** native Key skin packages (`.msp`, `free=false`).

---

## 功能特性 / Features

- **原生 Key 后端 (`free=false`)**：保留 Malody V 原生 `ProcessorKey`、判定、计分、Replay 与成绩机制，不使用旧 Free 兼容模式替代判定器或放行排名条件。
- **多键数 / 多平台 / 宽高比分支**：自动打包包内全部 `script-key-*K.mui` 键数、Windows / Android 入口与比例分支。
- **长条与贴图保真**：支持 Scale3 / Part3 / Scale3Part3 / Tile3 等原生与源队列几何，修正透明边缘溢色（black-fringe bleed）与图集半像素 UV 采样接缝，并在轨道无挡板时自动隐藏闲置默认挡板图元。
- **UI / 动画 / 字体**：还原通用自定义 UI、帧动画、缓动与斜切动画，内置 Source Han 24px 预烘焙字库与 Windows/OS 混合字体回退。
- **Key 音联动原生设置**：转换后的 `@best` / `@cool` / `@good` 打击音效（`type=5006`）实时遵循 Malody V 内置的 Key 音开关（`key_sound` / `skip_keysound`）与打击音量（`hit_volume`）。
- **4.3.7 暂停键与左上角隐藏触控区**：当 `.mui` 未定义 `pause` 且原皮肤自带 `ui-play-pause.png`（包括全透明占位图）时，在左上角按 4.3.7 布局生成可点击暂停区域；若原皮肤也无 `ui-play-pause.png`，则保留 MaV 原生默认暂停按钮。

---

## 快速使用 / Quick Start

### 方式 1：Windows 便携版（推荐 / Recommended）
前往 **Releases** 下载最新版 `Ma-Skin-Bridge-*-win-x64.zip` 解压后：
- **图形界面**：双击 `打开转换器.cmd`（或把 `.msz` 文件直接拖到 `MSZ转MSP.cmd` / 程序窗口），生成的 `.msp` 会输出在原 `.msz` 同级目录下（文件名空格自动规范为下划线以兼容 MaV 导入）。
- **命令行**：
  ```cmd
  ma-convert.cmd "你的皮肤.msz"
  ```

### 方式 2：从源码运行 / Run from Source
需要 Python 3.11+（仅依赖 `pillow` 与 `protobuf`）：

```bash
pip install -r requirements.txt

# 图形界面 / GUI
python "Ma Skin Bridge.pyw"

# 命令行转换 .msz / CLI (.msz -> .msp)
python -X utf8 ma_skin_bridge.py path/to/skin.msz -o output/
```

---

## 当前状态与已验证范围 / Status & Verification Scope

- **Windows 端实机与单元测试**：
  - 单元测试：`697` 项测试通过（解析、UI/动画/字体契约、多键数分支、Key 音联动 Lua 契约、暂停键回退等）。
  - 实机验证：在 Windows 原版 Malody V 客户端只读（`--read-only-install`）真实 `ScenePlay` 环境下，已验证多款真实 `.msz` 转换包可导入运行、无 Lua 报错，包含帧率表现、挡板/LN 接缝、Key 音开关同步以及左上角暂停热区。
- **尚未由工具替代验证的边界**：
  - 皮肤在线上传、普通联网成绩上传需玩家/作者在实际 Malody V 在线环境实测确认。
  - Android 实机环境端到端测试待后续补充。

---

## 仓库结构 / Repository Structure

- [ma_skin_bridge.py](ma_skin_bridge.py) — 命令行入口 / CLI entrypoint
- [Ma Skin Bridge.pyw](Ma%20Skin%20Bridge.pyw) — Tkinter 拖拽 GUI 入口 / Windows GUI entrypoint
- [converter/](converter/) — 核心解析器、原生 Key 编译器与内置 Lua 运行时脚本 / Core compiler & runtime Lua modules
- [converter/data/](converter/data/) — 协议描述与 4.3.7 缺省字体/资源包 / Skin protobuf descriptor, default assets & font bank
- [docs/STATUS.md](docs/STATUS.md) — 近期验证与状态摘要 / Recent verification status
- [tests/](tests/) — 核心回归测试集 / Regression tests

---

## 开源协议与致谢 / License & Credits

本项目源码采用 [MIT License](LICENSE) 开源。  
内置运行时字体与光栅库遵循各自原许可证：
- FreeType (`converter/data/FreeType-LICENSE.txt`)
- Source Han Sans (`converter/data/SourceHan-LICENSE.txt`)
