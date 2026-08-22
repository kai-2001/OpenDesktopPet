# Agent 通知橋接器

`codex_stop_notify.ps1`、`vscode_agent_notify.ps1`、`opencode_notify.ps1`、
`claude_code_notify.ps1`、`gemini_cli_notify.ps1` 與 `antigravity_cli_notify.ps1` 是 Open Desktop Pet 的 Windows 本機通知橋接器；`pi_agent_notify.ts` 是 Pi 的 TypeScript extension。Codex App、VS Code Codex、Codex CLI、VS Code Copilot、終端機 OpenCode、Claude Code、Gemini CLI、Antigravity CLI 與 Pi
共用桌寵的一個 `127.0.0.1` UDP 通訊埠；Pi extension 與其他橋接器都會先判斷來源與目標屬地，
桌寵再統一處理氣泡與視窗切換。

桌寵內開啟「Agent 通知」後，橋接器會將 Agent 的完成、等待或錯誤狀態
轉成 UDP 訊息送到桌寵設定的本機通訊埠。關閉功能或
桌寵正常結束時，橋接器不會傳送 UDP。橋接器不依賴任何固定專案路徑，
也不會轉送 Agent 回答、提示詞、程式碼或完整對話內容。

永久開關只儲存在 Godot 的 `ui_settings.cfg`。桌寵執行時才會在下列位置
建立唯一的執行期註冊；其中包含實例 ID、PID、UDP 埠與各來源的啟用狀態：

```text
%USERPROFILE%\.open-desktop-pet\open_desktop_pet_runtime.json
```

所有橋接器只讀這一份 runtime 檔。桌寵結束時只會刪除屬於自己的註冊，
不再將全域 `*_enabled.txt` 寫成 `0`；`.codex` 也不再保存桌寵的啟用旗標。

Codex 橋接器只記錄 Stop 事件、工作目錄與處理結果，診斷檔位於：

```text
%TEMP%\OpenDesktopPet-codex-stop-hook.log
```

Claude Code bridge 的診斷檔為 `%TEMP%\OpenDesktopPet-claude-code-notify.log`。
Gemini CLI bridge 的診斷檔為 `%TEMP%\OpenDesktopPet-gemini-cli-notify.log`。
Antigravity CLI bridge 的診斷檔為 `%TEMP%\OpenDesktopPet-antigravity-cli-notify.log`。

## 安裝 Codex 設定

使用者第一次安裝桌寵後，在這個資料夾開啟 PowerShell：

```powershell
.\install_codex_integration.ps1
```

一般使用者也可以直接雙擊：

```text
Install-Codex-Integration.cmd
```

桌寵會先在本機檢查橋接器、安裝標記與 Codex `hooks.json`，不會為了檢查而啟動 PowerShell。
只有檢查到檔案缺失或 Stop hook 失效時，才會自動執行安裝器。安裝器會把橋接器複製到
`%USERPROFILE%\.open-desktop-pet`，並只在 `%USERPROFILE%\.codex\hooks.json` 新增或更新
桌寵自己的非同步 `Stop` handler；原本的其他 hook 會保留。舊版 `notify` 桌寵橋接會在安裝時
自動遷移並移除，原本不屬於桌寵的 notify 命令則會保留。第一次安裝或修復後須重新啟動
VS Code 或 Codex，並依 Codex 提示檢閱及信任新的 hook。

第一次從桌寵開啟任一 Codex 通知時，桌寵會向 Codex 查詢 Hook 的實際信任狀態。
若尚未信任、內容已變更或被停用，開關不會顯示為成功；桌寵會顯示引導視窗，
由使用者開啟 Codex CLI、輸入 `/hooks` 並在 Codex 的官方審查頁面完成確認。
回到桌寵按「重新檢查」後，只有 Codex 回報 Hook 已啟用且為 `trusted`，才會真正開啟通知。

## 安裝 Pi extension

Pi 沒有像 Codex CLI 那樣的 `hooks.json` Stop Hook；Pi 目前是 terminal coding harness，整合方式是 TypeScript extension，一份 extension 可處理所有 provider 與模型。
桌寵會將 `pi_agent_notify.ts` 安裝到：

```text
%USERPROFILE%\.pi\agent\extensions\open-desktop-pet.ts
```

若設定 `PI_CODING_AGENT_DIR`，則會安裝到該資料夾的 `extensions` 子資料夾。
extension 使用 Pi 的 `agent_settled` 事件，等重試、壓縮及 queued follow-up 都完成後才通知，
並只傳送完成或錯誤狀態、session ID、工作目錄與模型識別，不傳送回答、提示詞或程式碼。
安裝後重新啟動 Pi，或在 Pi 內執行 `/reload`：

```powershell
.\install_pi_integration.ps1
```

解除安裝：

```powershell
.\install_pi_integration.ps1 -Uninstall
```

## 安裝 VS Code Copilot user hook

桌寵會先在本機檢查 Copilot hook 與橋接器；只有缺失或內容失效時，才會執行
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

## 安裝終端機 OpenCode Plugin

桌寵會先在本機檢查 OpenCode plugin 與橋接器；只有缺失或內容失效時，才會執行
`install_opencode_integration.ps1`。它會安裝：

```text
%USERPROFILE%\.config\opencode\plugins\open-desktop-pet.js
%USERPROFILE%\.open-desktop-pet\opencode_notify.ps1
```

Plugin 監聽 OpenCode 的 `session.idle` 與 `session.error` 事件，並將
`source = opencode` 的狀態送到桌寵共用 Port。橋接器會依 VS Code 環境、已驗證的
Desktop 程序或一般終端機決定 `target_app`；Desktop 路徑空白時只跳過 Desktop
判斷，不會阻擋其他 OpenCode 通知。
安裝後重新啟動 OpenCode 才會載入 Plugin。

OpenCode Desktop 的 Windows 下載檔目前叫做
`opencode-desktop-windows-x64.exe`；它是安裝器。桌寵會另外偵測安裝後的
`OpenCode.exe`，並查詢常用安裝路徑與 Windows 卸載登錄資訊，不會把 CLI 的
`opencode.exe` 當成 Desktop。

解除安裝 OpenCode Plugin：

```powershell
.\install_opencode_integration.ps1 -Uninstall
```

## 安裝 Claude Code hooks

桌寵會將 Claude Code 的 `Stop`、`Notification` 與 `StopFailure` hooks 安裝到：

```text
%USERPROFILE%\.claude\settings.json
```

CLI、VS Code Extension 與 Claude Desktop 的本機 Code session 共用這份設定；bridge
會依執行環境分流到終端機、VS Code 或 Claude Desktop。安裝方式：

```powershell
.\install_claude_code_integration.ps1
```

解除安裝：

```powershell
.\install_claude_code_integration.ps1 -Uninstall
```

Claude Code bridge 只送出完成、等待或錯誤狀態，不會將最後回答或完整對話內容傳給桌寵。

## 安裝 Gemini CLI 舊版 hooks

桌寵會將 Gemini CLI 的 `AfterAgent` 與 `Notification`（只匹配
`ToolPermission`）hooks 安裝到：

```text
%USERPROFILE%\.gemini\settings.json
```

Gemini CLI 舊版只支援終端機，適用於企業帳號或 API Key。安裝器會保留原本的 Gemini 設定與其他 hooks，
bridge 只送出完成或權限等待狀態，不會把回答或完整對話內容傳給桌寵：

```powershell
.\install_gemini_cli_integration.ps1
```

解除安裝：

```powershell
.\install_gemini_cli_integration.ps1 -Uninstall
```

安裝或解除安裝後請重新啟動 VS Code、Codex、OpenCode、Claude Code／Claude Desktop、Gemini CLI 或 Pi。

## 安裝 Antigravity CLI hooks

Antigravity CLI（命令為 `agy`）的通知使用官方 `Stop` hook，設定檔位於：

```text
%USERPROFILE%\.gemini\config\hooks.json
```

Antigravity CLI 只送出完成或錯誤狀態，不會把回答、提示詞或完整對話內容傳給桌寵。安裝器會保留其他 hooks，
只管理自己的 `open-desktop-pet` hook：

```powershell
.\install_antigravity_cli_integration.ps1
```

解除安裝：

```powershell
.\install_antigravity_cli_integration.ps1 -Uninstall
```

安裝或解除安裝後請重新啟動 Antigravity CLI。桌寵的開關仍採懶載入，只有開啟通知且缺少或失效時才會執行安裝器。

## 解除安裝 OpenDesktopPet

可攜式版本仍會在使用者資料夾寫入 Agent 通知 hook、橋接器、桌寵設定、存檔與角色包。
若不再使用桌寵，請雙擊：

```text
Uninstall-OpenDesktopPet.cmd
```

解除安裝器會讓使用者選擇：

1. **只移除 Agent 通知整合與開機啟動**：撤回 Codex、Copilot、OpenCode、Claude Code、Gemini CLI、Antigravity CLI 與 Pi 的桌寵整合，保留角色包、存檔與桌寵設定。
2. **完整移除**：除了上述整合，也會刪除 `%USERPROFILE%\.open-desktop-pet`、Godot 的桌寵資料（`ui_settings.cfg`、`profiles`、`character_packs`）及桌寵診斷記錄。

也可在 PowerShell 直接指定模式：

```powershell
.\uninstall_open_desktop_pet.ps1 -Mode Integrations
.\uninstall_open_desktop_pet.ps1 -Mode Complete
```

兩種模式都只會移除 OpenDesktopPet 寫入各 Agent 設定檔的項目，不會刪除整個
`.codex`、`.copilot`、`.claude`、`.gemini` 或 OpenCode 資料夾。完成後，請自行刪除
解壓縮的可攜式發布資料夾；解除安裝器不能在執行中刪除自己的檔案。

## 通知 payload

所有橋接器都送出同一組基本欄位：`schema_version`、`type`、`agent`、`source`、
`target_app`、`target_platform`、`target_executable`、`event_id`、`thread_id`、
`turn_id`、`session_id` 與 `cwd`。桌寵使用 `agent` 判斷顯示名稱，使用 `target_app`
判斷點擊氣泡後要切回的執行檔平台。

## 發布 EXE 時

發布壓縮檔請保留以下結構，讓其他使用者可以直接安裝：

```text
OpenDesktopPet.exe
open_desktop_pet_windows.windows.template_release.x86_64.dll
tools/
├─ Uninstall-OpenDesktopPet.cmd
├─ uninstall_open_desktop_pet.ps1
├─ Install-Codex-Integration.cmd
├─ install_codex_integration.ps1
├─ codex_stop_notify.ps1
├─ install_copilot_integration.ps1
├─ vscode_agent_notify.ps1
├─ install_opencode_integration.ps1
├─ opencode_notify.ps1
├─ opencode_notify_plugin.js
├─ Install-Claude-Code-Integration.cmd
├─ install_claude_code_integration.ps1
├─ claude_code_notify.ps1
├─ Install-Gemini-CLI-Integration.cmd
├─ install_gemini_cli_integration.ps1
├─ gemini_cli_notify.ps1
├─ Install-Antigravity-CLI-Integration.cmd
├─ install_antigravity_cli_integration.ps1
├─ antigravity_cli_notify.ps1
├─ Install-Pi-Integration.cmd
├─ install_pi_integration.ps1
└─ pi_agent_notify.ts
```

若已有建置好的 EXE，可以用以下指令準備發布資料夾：

```powershell
.\prepare_windows_release.ps1
```

它會建立 `build/release-codex`，再將該資料夾壓縮發布即可。

安裝器會使用使用者自己的 `%USERPROFILE%` 或 `CODEX_HOME`，不會寫入開發者
電腦的路徑，也不需要知道桌寵 EXE 安裝在哪裡。

## 手動設定

在使用者的 Codex hook 設定檔：

```text
%USERPROFILE%\.codex\hooks.json
```

加入以下內容，將路徑換成實際安裝位置：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\\\Apache24\\\\htdocs\\\\OpenDesktopPet\\\\tools\\\\codex_stop_notify.ps1\"",
            "commandWindows": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\\\Apache24\\\\htdocs\\\\OpenDesktopPet\\\\tools\\\\codex_stop_notify.ps1\"",
            "async": true,
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Codex App、Codex IDE 擴充功能與 Codex CLI 共用這個 Stop hook。它只在一輪聊天停止時通知，
不會把中途的模型工具往返誤當成完成。桌寵會依來源
開關決定是否轉發：VS Code Codex 轉回 VS Code、Codex App 轉回 Codex App，
外部 Codex CLI 轉回終端機。從 VS Code 內建終端機啟動的 CLI 會歸到 VS Code。

若不想再使用通知，請執行 `install_codex_integration.ps1 -Uninstall`；它只移除桌寵自己的
Stop handler，不會刪除其他 Codex hooks。完成後重新啟動 Codex 或 VS Code。

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
