# Windows 桌寵 GDExtension

這個模組包含兩個 Windows 功能：使用 Win32 API 尋找設定頁所指定的 VS Code
執行檔視窗，並在使用者點擊通知氣泡時把該視窗切到前景；以及監聽系統喚醒事件，
供 `scripts/display_recovery_controller.gd` 在螢幕保護裝置結束或系統喚醒後重新套用透明視窗設定。執行階段不會啟動
PowerShell、CMD 或常駐的外部輔助程序，也不會取消桌寵的永遠置頂設定。

電源事件監聽器會在桌寵程序內建立一個隱藏視窗接收 Windows 通知，並在獨立訊息執行緒
處理事件；螢幕保護裝置狀態則由主程式每半秒查詢一次。恢復事件與透明設定重套用紀錄
會附加到 `user://display_recovery.log`。

## 編譯

在 Windows PowerShell 由專案根目錄執行：

```powershell
.\native\windows\build_windows.ps1
```

腳本只供開發時手動編譯。它會把固定版本的 `godot-cpp 4.5 stable` 與
LLVM-MinGW 下載到已被 Git 忽略的 `build/native-deps`，驗證工具鏈 SHA-256，
再依照最小化 build profile 產生 debug 與 release x64 DLL 到
`native/windows/bin`。build profile 只啟用這個模組與 godot-cpp 核心所需的
`RefCounted`、`OS` 類別，不會編譯整套用不到的 Godot 類別。
