# Codex 通知橋接器

`codex_notify.ps1` 是 Open Desktop Pet 與 Codex 的 Windows 本機通知橋接器。

桌寵內開啟「Codex 完成通知」後，它會將 Codex 的
`agent-turn-complete` 轉成 UDP 訊息送到桌寵設定的本機通訊埠。關閉功能或
桌寵正常結束時，橋接器不會傳送 UDP。橋接器不依賴任何固定專案路徑，
也不會轉送 Codex 回答、提示詞、程式碼或完整對話內容。

橋接器只記錄事件類型、工作目錄與處理結果，診斷檔位於：

```text
%TEMP%\OpenDesktopPet-codex-notify.log
```

## 安裝 Codex 設定

使用者第一次安裝桌寵後，在這個資料夾開啟 PowerShell：

```powershell
.\install_codex_integration.ps1
```

一般使用者也可以直接雙擊：

```text
Install-Codex-Integration.cmd
```

第一次在桌寵內開啟通知時，程式會自動執行安裝器。安裝器會把橋接器複製到
使用者的 `%USERPROFILE%\.codex`，並更新該使用者的 Codex `config.toml`。
若原本已有不同的 `notify` 設定，會先建立可還原的備份；重複啟用相同設定
不會反覆建立備份。第一次安裝後仍須重新啟動 VS Code 或 Codex。

解除安裝：

```powershell
.\install_codex_integration.ps1 -Uninstall
```

安裝或解除安裝後請重新啟動 VS Code/Codex。

## 發布 EXE 時

發布壓縮檔請保留以下結構，讓其他使用者可以直接安裝：

```text
OpenDesktopPet.exe
open_desktop_pet_windows.windows.template_release.x86_64.dll
tools/
├─ Install-Codex-Integration.cmd
├─ install_codex_integration.ps1
└─ codex_notify.ps1
```

若已有建置好的 EXE，可以用以下指令準備發布資料夾：

```powershell
.\prepare_windows_release.ps1
```

它會建立 `build/release-codex`，再將該資料夾壓縮發布即可。

安裝器會使用使用者自己的 `%USERPROFILE%` 或 `CODEX_HOME`，不會寫入開發者
電腦的路徑，也不需要知道桌寵 EXE 安裝在哪裡。

## 手動設定

在使用者的 Codex 設定檔：

```text
%USERPROFILE%\.codex\config.toml
```

加入以下內容，將路徑換成實際安裝位置：

```toml
notify = [
  "powershell.exe",
  "-NoProfile",
  "-File",
  "C:\\Apache24\\htdocs\\OpenDesktopPet\\tools\\codex_notify.ps1"
]
```

Codex IDE 擴充功能與 Codex CLI 共用這個通知設定。桌寵必須正在執行，且
桌寵會在收到通知後顯示「Codex 完成了這一輪，可以切回 VS Code 看結果。」。

若不想再使用通知，從 `config.toml` 移除 `notify` 設定後重新啟動 Codex
或 VS Code 即可。
