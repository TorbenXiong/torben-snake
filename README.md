# Torben Snake

使用 Godot 4.7.2 制作的霓虹风格闯关贪吃蛇，支持 Windows x86_64 和 Web。当前版本：**0.0.1**。

## 游玩

- 菜单：点击关卡，或用方向键 / `WASD` 选择，按 `Enter` 开始。
- 移动：方向键 / `WASD`、触屏滑动或屏幕方向按钮。蛇身连续移动，输入立即转向，禁止直接反向。
- 暂停：`Space` / `Esc` 或暂停按钮；窗口失焦时自动暂停。
- 结算：`Enter` 重试本关、进入下一关或重新闯关，也可返回菜单。

共六关，食物目标依次为 5、7、8、9、10、12，速度逐关提升，后四关加入随机障碍。收集目标数量后通关，撞到边界、障碍或自身则失败。

金色食物 +10；粉色食物 +25，8 秒后变为普通食物；青色食物 +15，并减速 5 秒。每份食物增长一格。选关从零分开始，连续闯关保留累计分，失败重试恢复到本关起始分。

最高分与已解锁关卡自动保存至 `user://torben_snake.cfg`。Windows 默认位于 `%APPDATA%\Godot\app_userdata\Torben Snake\`；Web 按站点保存在浏览器中，清除站点数据会清除记录。

## 开发与导出

用 Godot 4.7.2 打开 `project.godot`，按 `F5` 运行。项目使用 Compatibility 渲染器，无额外运行时依赖；导出前需通过 Godot 安装同版本的本地导出模板。

在项目目录执行以下 **PowerShell** 命令，将路径替换为本机 Godot 可执行文件：

```powershell
$godot = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
& $godot --headless --path . --script tests/test_game.gd
& $godot --headless --path . --script tests/test_ui.gd
# 导入、测试、导出并生成发布包及 SHA-256 校验文件
.\tools\export.ps1 -GodotPath $godot
```

测试覆盖连续运动、即时转向、碰撞、食物、六关推进、分数回退、选关解锁、输入、暂停及存档，使用独立测试存档。图形验收可运行：

```powershell
& $godot --path . --script tests/test_ui.gd -- --capture
& $godot --path . --resolution 390x844 --script tests/test_ui.gd -- --capture --portrait
```

截图位于 `build/qa/`；将 `--capture` 替换为 `--capture-motion` 可捕获连续转弯帧。自动化覆盖不代表真实手机或全部浏览器已验收。

发布文件位于 `build/release/0.0.1/`：Windows 单文件 EXE、Web ZIP、字体许可 `OFL.txt` 与 `SHA256SUMS.txt`。构建脚本只使用本地工具与模板，不下载内容。版本由 `project.godot` 的 `config/version` 定义。

## Web 部署

解压 Web ZIP，将全部内容部署到 HTTP(S) 服务器；不能直接双击 `index.html`。服务器须提供 `.wasm` 的 `application/wasm` MIME 类型。单线程导出无需 COOP/COEP，浏览器须支持 WebAssembly 和 WebGL 2.0；音效在首次用户操作后启用。

本机已有 Python 时，可用 **PowerShell** 启动预览：

```powershell
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

访问 <http://localhost:8765/>。

## 结构与资源

- `scripts/game_logic.gd`：关卡、连续轨迹、碰撞与食物。
- `scripts/main.gd`：绘制、输入、界面与程序化音效。
- `scripts/score_store.gd`：最高分和解锁记录。
- `tests/`：Godot 原生测试；`tools/export.ps1`：构建与打包。

图标由项目绘制，画面由 Godot 2D 绘制。中文字体 Noto Sans SC 使用 SIL OFL 1.1，许可见 `assets/fonts/OFL.txt`，分发时须保留。版本记录见 [CHANGELOG.md](CHANGELOG.md)。
