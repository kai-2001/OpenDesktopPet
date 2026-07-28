# Open Desktop Pet

一個使用 Godot 4 製作、以 Windows 為第一目標平台的開源可自訂桌寵引擎。
專案核心不綁定特定角色、作品或素材，使用者可以透過角色包替換外觀與動畫。

目前包含：

- 透明、無邊框、置頂桌寵視窗
- 拖曳、雙擊摸摸、右鍵操作面板
- 飽食、水分、體力、心情、金幣、經驗與等級
- 餵食、喝水、睡覺、工作和拍手互動
- JSON 自動存檔與有限度離線狀態推進
- 可公開散佈的通用預設角色
- 與 Git 完全隔離的私人角色包

## 開發

需要 Godot 4.6.3 或相容的 4.6 穩定版：

```powershell
godot --editor --path .
godot --path .
```

完整自動驗證會使用獨立的暫存 AppData，不會讀寫正式進度：

```powershell
.\tests\run_validation.ps1 -GodotExe C:\path\to\Godot_v4.6.3-stable_win64_console.exe
```

驗證包含真實動畫完成結算、動畫拒絕、願望到期、安全存檔與備份、
首次開啟詳細面板、透明區域 hitbox，以及正式存檔前後 SHA-256 比對。

## 角色素材

`private_pets/` 已被 `.gitignore` 排除，不得提交到公開儲存庫或 Release。
開發環境可從下列設定檔載入私人角色包：

```text
private_pets/active/pet.json
```

打包後的使用者角色包放在：

```text
%APPDATA%\Godot\app_userdata\Open Desktop Pet\characters\active\pet.json
```

載入優先順序為外部使用者角色、開發用私人角色、最後是公開版內建的
中性預設角色。無效或缺少必要動作的角色包會被拒絕並自動回退。

角色包包含八個基本動作，也能加入受等級與親密度限制的額外動作。完整格式請參考 [`docs/CHARACTER_PACK.md`](docs/CHARACTER_PACK.md) 與 [`examples/character-pack/pet.json`](examples/character-pack/pet.json)。

## 授權

程式碼採 MIT License。第三方及私人角色素材不因程式碼授權而取得再散佈權利。
提交變更前請確認素材具有相容的公開授權，或僅放在被忽略的 `private_pets/`。

## 版本控制

公開提交只包含引擎、通用 UI、遊戲邏輯、文件與可再散佈素材。
`.godot/`、建置輸出、日誌與 `private_pets/` 不會進入 Git。
