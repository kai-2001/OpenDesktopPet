# Contributing

感謝你參與 Open Desktop Pet。

## 原則

- 公開核心不得依賴私人或不可再散佈的角色素材。
- 新功能應在沒有 `private_pets/` 時仍可執行。
- 提交前以 Godot 4.6 穩定版載入專案，確認沒有腳本或場景錯誤。
- UI 需支援 Windows 顯示縮放，並避免透明視窗攔截不必要的桌面操作。
- 請勿提交 `.godot/`、`build/`、日誌或本機存檔。

## 提交流程

1. 建立功能分支。
2. 完成功能及必要文件。
3. 執行 Godot headless 驗證。
4. 確認 `git status` 沒有私人素材。
5. 提交清楚、單一目的的 commit。

