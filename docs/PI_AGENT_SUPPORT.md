# Pi Agent 通知支援

Pi 沒有像 Codex CLI 那樣的 `hooks.json` Stop Hook；Pi 的官方整合方式是放置 TypeScript
extension，使用 `agent_settled` 生命週期事件。Pi 目前是 terminal coding harness，支援互動式 TUI、print／JSON、RPC 與 SDK 模式；本整合針對在終端機執行的 Pi。

OpenDesktopPet 提供 `tools/pi_agent_notify.ts`，安裝到：

```text
%USERPROFILE%\.pi\agent\extensions\open-desktop-pet.ts
```

如果 Pi 使用 `PI_CODING_AGENT_DIR`，則安裝器會使用該資料夾。

## 通知流程

1. 使用者在桌寵「Agent 通知」頁開啟「Pi」。
2. 桌寵執行 `install_pi_integration.ps1`。
3. Pi extension 監聽 `agent_settled`。
4. extension 讀取桌寵的 runtime registration。
5. 只有桌寵仍在執行且 `pi_codex_terminal` 已啟用時，才送出 `127.0.0.1` UDP 通知；這個設定鍵沿用既有名稱，但代表所有 Pi 模型。成功與錯誤會分別送出完成或錯誤狀態。

`agent_settled` 比 `agent_end` 更適合桌寵：它會等自動重試、context compaction 及 queued
follow-up 都結束，避免太早顯示完成通知。

通知 payload 不包含提示詞、回答、工具輸出或程式碼，只包含完成狀態、Pi session ID、工作目錄
及模型識別，因此同一份 extension 可處理所有 Pi provider 與模型。點擊通知氣泡時，桌寵會依共用的終端機 executable path 切回 Windows Terminal。

## 手動安裝與解除安裝

```powershell
.\tools\install_pi_integration.ps1
.\tools\install_pi_integration.ps1 -Uninstall
```

安裝器只會管理自己寫入的 extension；如果原本已有同名 extension，會先備份，解除安裝時恢復。
