# Codex Pet 素材包支援

OpenDesktopPet 現在可以直接匯入 Codex Pet 的 ZIP。ZIP 根目錄需要包含：

- `pet.json`
- `spritesheet.png` 或 `spritesheet.webp`

判斷方式是讀取 UTF-8 的 `pet.json`：有 `spritesheetPath` 且沒有自製包的 `actions` 物件，就視為 Codex Pet；自製角色包的 `format_version` 與 `actions` 格式仍維持不變。

Codex spritesheet 會依標準 192×208 格切成 8 欄。v1 必須是 8×9（1536×1872），v2 必須是 8×11（1536×2288）。匯入器會把標準列轉成專案動作：

| 專案動作 | Codex 素材 |
| --- | --- |
| idle | idle 列 |
| move / drag | running-right 列（row 1，左向時翻轉） |
| work | running 列（row 7） |
| jumping / pet | jumping 列 |
| eat / drink / sleep | idle 列，加上 OpenDesktopPet 共用特效 |

共用特效位於 `assets/effects/`，會依角色包尺寸自動縮放：睡覺加眼罩與飄出的 `zzz`，吃飯加食物晃動後消失，喝水加水杯晃動後消失。

Codex 動作目前以提供的動畫影片測得的速度作為基準：每格約 250ms。一般 idle 會每 250ms 切換一格；影片本身是 30 FPS、4 秒，錄到約 16 個視覺切換段，首尾不完整的取樣誤差不納入基準。

Codex 包可另外放置選用的 `open_desktop_pet.json`，只由 OpenDesktopPet 讀取，不會改變原生 Codex `pet.json`：

```json
{
  "behavior": {
    "autonomous_chance": 0.35
  },
  "effects": {
    "food": {
      "file": "effects/food.png",
      "anchor": [-31, 14],
      "scale": 0.52
    }
  }
}
```

未設定時，Codex Pet 每次符合自主行為條件的抽選有 35% 機率移動；特效則使用共用素材。設定檔可以只覆寫某一個效果，其餘仍沿用共用預設。
