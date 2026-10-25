# Windows 桌寵 GDExtension

這個模組包含兩個 Windows 功能：使用 Win32 API 尋找設定頁所指定的 VS Code
執行檔視窗，並在使用者點擊通知氣泡時把該視窗切到前景；以及監聽系統喚醒事件，
供 `scripts/display_recovery_controller.gd` 在螢幕保護裝置結束或系統喚醒後重新套用透明視窗設定。執行階段不會啟動
PowerShell、CMD 或常駐的外部輔助程序，也不會取消桌寵的永遠置頂設定。

電源事件監聽器會在桌寵程序內建立一個隱藏視窗接收 Windows 通知，並在獨立訊息執行緒
處理事件；螢幕保護裝置狀態則由主程式每半秒查詢一次。恢復事件與透明設定重套用紀錄
會附加到 `user://display_recovery.log`。

## 點擊穿透

`WindowsClickThrough` 依滑鼠是否在角色或對話框上，切換桌寵視窗的
`WS_EX_LAYERED | WS_EX_TRANSPARENT`，讓空白處的點擊落到其他程式。這取代了
Godot 的 `mouse_passthrough_polygon`：在 Windows 上它是 `SetWindowRgn`，會連畫面
一起裁切，造成對話框殘影與角色缺角。

使用時視窗區域要維持 `DesktopWindowService.unclipped_region()` 這個超大矩形，
不能清空：Godot 清空區域時呼叫 `SetWindowRgn(nullptr, TRUE)` 強制重畫，與切換
穿透同時發生時，DWM 會顯示一格灰色的視窗底色。設定多邊形則不強制重畫。

分層視窗改變大小時，若同一格 GPU 正在上傳新的字形或圖片，Windows 會顯示一格
半透明白色的空白畫面。因此原生模式下 `PetVisual.use_fixed_window()` 會在角色載入時，
一次把視窗設成所有動作在最大倍率都放得下的大小，之後動作、拖曳、調整倍率都不再
改變視窗大小；真的需要改變大小時（啟動、切換成更大的角色），`main.gd` 會先用
`set_opacity` 把整個視窗設成全透明，幾格後再恢復。

`tests/run_native_click_through_test.ps1` 會開真實視窗並移動滑鼠，驗證透明、穿透、
拖曳、角色大小與 FPS；它不在 `run_validation.ps1` 內，需要手動執行。

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
