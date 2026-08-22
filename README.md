# Open Desktop Pet

一個使用 Godot 4 製作、以 Windows 為第一目標平台的開源可自訂桌寵引擎。
專案核心不綁定特定角色、作品或素材，使用者可以透過角色包替換外觀與動畫。

目前包含：

- 透明、無邊框、置頂桌寵視窗
- 拖曳、雙擊摸摸、右鍵操作面板
- 飽食、水分、體力、心情、金幣、經驗與等級
- 餵食、喝水、工作和摸摸互動，以及可喚醒、逐步恢復體力的睡眠系統
- JSON 自動存檔，離線期間照顧狀態與親密進度凍結
- 可公開散佈的通用預設角色
- 支援 Codex Pets 素材
- Agent 通知整合：Codex、OpenCode、Claude Code、Gemini CLI、Antigravity CLI、Copilot 與 Pi
- 遊戲內匯入、更新、切換與刪除角色包
- 與 Git 完全隔離的私人角色包

## 開發

需要 Godot 4.6.3 或相容的 4.6 穩定版：

```powershell
godot --editor --path .
godot --path .
```

完整自動驗證會使用獨立的暫存 AppData，不會讀寫正式進度：

```powershell
.\tests\run_validation.ps1 -GodotExe (Get-Command godot).Source
```

驗證包含真實動畫完成結算、動畫拒絕、願望到期、安全存檔與備份、
首次開啟詳細面板、透明區域 hitbox，以及正式存檔前後 SHA-256 比對。

## 角色素材

`characters/custom/` 已被 `.gitignore` 排除，不得提交到公開儲存庫或 Release。
開發環境可從下列設定檔載入私人角色包：

```text
characters/custom/pet.json
```

正式版本可從詳細面板的「角色」頁匯入 `.petpack` 或 ZIP。程式驗證後會安裝到：

```text
%APPDATA%\Godot\app_userdata\Open Desktop Pet\character_packs\<角色ID>\
```

目前角色由 `ui_settings.cfg` 內的角色 ID 明確選擇；找不到或無法載入時會回退到
公開版內建角色。相同 ID 的匯入包會視為更新，替換角色圖片與設定但保留進度。
角色清單只在使用者開啟角色頁時掃描，不增加平常常駐輪詢。

角色包包含八個基本動作，也能加入受等級與親密度限制的額外動作。完整格式請參考 [`docs/CHARACTER_PACK.md`](docs/CHARACTER_PACK.md) 與 [`examples/character-pack/pet.json`](examples/character-pack/pet.json)。

## 授權

程式碼採 MIT License。第三方及私人角色素材不因程式碼授權而取得再散佈權利。
提交變更前請確認素材具有相容的公開授權，或僅放在被忽略的 `characters/custom/`。

## 版本控制

公開提交只包含引擎、通用 UI、遊戲邏輯、文件與可再散佈素材。
`.godot/`、建置輸出、日誌與 `characters/custom/` 不會進入 Git。
