# Agent 通知橋接器

`codex_notify.ps1` 與 `vscode_agent_notify.ps1` 是 Open Desktop Pet 的 Windows
本機通知橋接器。Codex App、VS Code Codex、Codex CLI 與 VS Code Copilot
共用桌寵的一個 `127.0.0.1` UDP 通訊埠；橋接器會先判斷來源與目標屬地，
桌寵再統一處理氣泡與視窗切換。

桌寵內開啟「Agent 通知」後，它會將 Codex 的
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

第一次在桌寵內開啟任一個 Codex 通知來源時，程式會自動執行安裝器。安裝器會把橋接器複製到
使用者的 `%USERPROFILE%\.codex`，並更新該使用者的 Codex `config.toml`。
若原本已有不同的 `notify` 設定，會先建立可還原的備份；重複啟用相同設定
不會反覆建立備份。第一次安裝後仍須重新啟動 VS Code 或 Codex。

## 安裝 VS Code Copilot user hook

第一次在桌寵內開啟 Copilot 通知時，程式會自動執行
`install_copilot_integration.ps1`。它會把 hook 設定放在使用者層級的：

```text
%USERPROFILE%\.copilot\hooks\open-desktop-pet.json
```

橋接腳本會放在 `%USERPROFILE%\.open-desktop-pet`。安裝器會保留同一個資料夾
裡原本的其他 hook，只新增或更新桌寵自己的 `Stop` hook；解除安裝也只移除
桌寵自己的項目。重新載入 VS Code 後，Copilot 每次完成一輪就會通知桌寵。

解除安裝 Codex：

```powershell
.\install_codex_integration.ps1 -Uninstall
```

解除安裝 Copilot user hook：

```powershell
.\install_copilot_integration.ps1 -Uninstall
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
├─ codex_notify.ps1
├─ install_copilot_integration.ps1
└─ vscode_agent_notify.ps1
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

Codex App、Codex IDE 擴充功能與 Codex CLI 共用這個通知設定。桌寵會依來源
開關決定是否轉發：VS Code Codex 轉回 VS Code、Codex App 轉回 Codex App，
外部 Codex CLI 轉回終端機。從 VS Code 內建終端機啟動的 CLI 會歸到 VS Code。

若不想再使用通知，從 `config.toml` 移除 `notify` 設定後重新啟動 Codex
或 VS Code 即可。

## VS Code Agent Hook 測試

Copilot 的 user hook 會讓 VS Code Agent 在一輪執行結束時觸發
`vscode_agent_notify.ps1`。這個 hook 只讀取 VS Code 傳入的事件資訊，送出
完成狀態，不會攔截、修改或阻止 agent。

測試方式：

1. 啟動桌寵，在「Agent 通知」頁開啟 Copilot，等待安裝完成。
2. 重新載入 VS Code 視窗，或執行 `Developer: Reload Window`。
3. 在 Copilot Chat 送出一個簡單問題，等待它完成。

VS Code hook 的診斷記錄位於：

```text
%TEMP%\\OpenDesktopPet-vscode-hook.log
```

VS Code Agent Hooks 目前是 Preview 功能；若沒有觸發，請到 Output 面板查看
`GitHub Copilot Chat Hooks`，或執行 `Developer: Show Agent Debug Logs`。
