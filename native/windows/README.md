# Windows 視窗切換 GDExtension

這個模組載入桌寵自己的程序，使用 Win32 API 尋找設定頁所指定的 VS Code
執行檔視窗，並在使用者點擊通知氣泡時把該視窗切到前景。執行階段不會啟動
PowerShell、CMD 或常駐的輔助程序，也不會取消桌寵的永遠置頂設定。

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
