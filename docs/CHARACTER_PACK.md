# 角色包格式 v1

每個角色包是一個資料夾。將使用中的角色包內容放到：

```text
private_pets/active/
├─ pet.json
└─ animations/
   ├─ idle.png
   ├─ pet.png
   ├─ eat.png
   ├─ drink.png
   ├─ sleep.png
   ├─ move.png
   ├─ drag.png
   └─ work.png
```

`private_pets/` 已被 Git 忽略，私人角色圖片不會包含在開源程式碼或 Release。

已打包 EXE 的外部角色包則放到：

```text
%APPDATA%\Godot\app_userdata\Open Desktop Pet\characters\active\
├─ pet.json
└─ animations\
```

程式依序嘗試 `user://characters/active/`、開發用
`res://private_pets/active/`、公開內建 `res://characters/default/`。
前一個角色包驗證失敗時會回退到下一個，不會帶著半套設定繼續執行。

## 必要動作

`pet.json` 的 `actions` 必須包含以下八個 ID：

| ID | 用途 |
|---|---|
| `idle` | 待機與眨眼 |
| `pet` | 被摸後的反應 |
| `eat` | 吃東西 |
| `drink` | 喝水 |
| `sleep` | 睡覺 |
| `move` | 自主移動 |
| `drag` | 被拖曳 |
| `work` | 工作 |

圖片可以使用任意檔名，但建議和動作 ID 相同。不同動作也可以引用同一張 Sprite Sheet 的不同影格。

## 動作設定

```json
{
  "format_version": 1,
  "id": "my_pet",
  "name": "我的桌寵",
  "scale": 0.31,
  "fallback_action": "idle",
  "actions": {
    "idle": {
      "file": "animations/idle.png",
      "columns": 4,
      "rows": 1,
      "sequence": [0, 1, 2, 1],
      "idle_interval": 2.6,
      "frame_time": 0.15,
      "offsets": [[0, 0], [0, 0], [0, 0], [0, 0]]
    }
  }
}
```

- `file`：相對於角色包根目錄的 PNG 路徑。
- `columns`、`rows`：Sprite Sheet 的欄數與列數。
- `sequence`：播放的影格索引，可重複或跳過影格。
- `frame_time`：每格秒數。
- `idle_interval`：待機表情切換間隔，僅用於 `idle`。
- `scale`：此動作的顯示比例；省略時使用角色包的全域 `scale`。
- `offsets`：每格 `[x, y]` 校正值，用於消除生成圖片中心不一致造成的跳動。
- `behavior: "pulse"`：固定姿勢搭配輕微呼吸縮放，適合只有一格的吃飯或喝水。
- `pulses`：`pulse` 重複次數。

角色包會在載入時驗證檔案存在、相對路徑安全、欄列數、影格範圍、
播放速度、pulse 次數、offset 格式與 fallback。`frame_time` 必須大於
0 且不超過 5 秒，單一 sequence 與 pulses 最多 120 次。

照顧獎勵會等角色包的實際動畫播放完成後才結算，不需要在遊戲邏輯中
另外填寫動作秒數。

## 額外動作與解鎖

八個必要動作以外的 ID 都視為額外動作：

```json
{
  "file": "animations/belly_clap.png",
  "columns": 4,
  "sequence": [0, 1, 2, 3, 2, 3, 1, 0],
  "frame_time": 0.17,
  "autonomous_weight": 20,
  "unlock": {
    "level": 3,
    "affection": 15
  }
}
```

- `autonomous_weight` 大於 0 時，該動作會加入自主動作抽選；數字越大越常出現。
- `unlock.level` 是最低等級。
- `unlock.affection` 是最低親密度。
- 未達條件的動作不會被自主抽中，直接要求播放時則改播 `fallback_action`。
- `move` 只有在滑鼠停止時才會被抽中；其他原地動作不受滑鼠移動限制。

## 別名

舊名稱或多個事件可以指向同一個動作：

```json
{
  "aliases": {
    "clap": "pet",
    "happy": "pet",
    "roll": "move"
  }
}
```

## 最低製作流程

1. 複製 `examples/character-pack/pet.json`。
2. 準備八組基本 Sprite Sheet。
3. 修改每組的欄列數、播放順序與速度。
4. 將角色包內容放入 `private_pets/active/`。
5. 原始碼開發使用 `DesktopPet.vbs`；已打包版本放入 AppData 路徑後重啟 EXE。
6. 若眨眼或動作發生位移，填寫每格 `offsets`。

食物替換、配件掛點和造型圖層不屬於格式 v1，會在下一階段擴充，避免目前角色作者需要處理組合爆炸。
