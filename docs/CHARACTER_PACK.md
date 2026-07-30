# 角色包格式 v1

Open Desktop Pet 的正式版本只需要內建公開角色。使用者可在詳細面板的「角色」頁匯入
`.petpack`或`.zip`角色包，程式會將通過驗證的內容安裝到：

```text
%APPDATA%\Godot\app_userdata\Open Desktop Pet\character_packs\<角色ID>\
```

一般使用者不需要手動操作 AppData。角色頁提供匯入、切換、逐一刪除與開啟角色資料夾。
角色清單只在開啟該頁時掃描，不會增加桌寵平常常駐的輪詢負擔。

## 封裝結構

`.petpack`實際上是 ZIP 檔，`pet.json`必須直接位於壓縮檔根目錄：

```text
PinkGirl.petpack
├─ pet.json
├─ preview.png
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

不要把最外層角色資料夾一起壓入 ZIP。

## 基本資訊

```json
{
  "format_version": 1,
  "id": "pink_cat_headset_girl",
  "name": "粉紅貓耳耳機少女",
  "version": "1.1.0",
  "preview": "preview.png",
  "scale": 0.36,
  "source_facing": "left",
  "fallback_action": "idle",
  "actions": {}
}
```

- `format_version`：目前固定為`1`。
- `id`：永久識別碼，只能使用小寫英文字母、數字、底線與連字號。
- `name`：顯示名稱，可以在更新時修改。
- `version`：顯示用角色包版本，建議採`主版.次版.修正版`。
- `preview`：選填的小型預覽圖，建議不超過256×256。
- `scale`：角色顯示比例。
- `source_facing`：原圖面向，可使用`left`或`right`。
- `fallback_action`：缺少選填動作時使用的替代動作。

判斷是否為同一角色只看`id`：

```text
ID不同 → 安裝新角色
ID相同 → 顯示確認後更新／重新安裝
```

更新只替換`character_packs/<ID>`，不會修改`profiles/<ID>/save_v2.json`。

## 必要動作

`actions`必須包含：

| ID | 用途 |
|---|---|
| `idle` | 待機 |
| `pet` | 摸頭 |
| `eat` | 吃東西 |
| `drink` | 喝水 |
| `sleep` | 睡覺 |
| `move` | 自主移動 |
| `drag` | 拖曳 |
| `work` | 工作 |

每個動作至少需要`file`，並可設定Sprite Sheet格線與播放順序：

```json
{
  "file": "animations/idle.png",
  "columns": 2,
  "rows": 2,
  "sequence": [0, 1, 2, 3, 2, 1],
  "frame_time": 0.16,
  "idle_interval": 0.22
}
```

- `file`必須是角色包內的相對路徑，不能使用`..`、絕對路徑或反斜線。
- 外部角色包支援PNG、JPG、JPEG、WebP與SVG。
- `columns`、`rows`描述Sprite Sheet格線。
- `sequence`描述播放影格索引，最多120項。
- `frame_time`為每個影格秒數。
- `behavior: "pulse"`可搭配`pulses`使用。
- `autonomous_weight`大於0時，該動作可由桌寵自主觸發。

動作可單獨覆寫原圖面向：

```json
{
  "file": "animations/move.png",
  "source_facing": "right"
}
```

## 解鎖條件

額外動作可設定等級及親密度：

```json
{
  "file": "animations/belly_clap.png",
  "columns": 4,
  "sequence": [0, 1, 2, 3],
  "frame_time": 0.17,
  "autonomous_weight": 20,
  "unlock": {
    "level": 3,
    "affection": 15
  }
}
```

## 互動文字與對話

角色包可透過`interactions`自訂五種互動的名稱、圖示與願望文字，也能透過
`dialogue`自訂啟動、單擊、待機及動作完成訊息。完整欄位可參考
`examples/character-pack/pet.json`。

## 安全限制

匯入器會先解壓到暫存資料夾並完整驗證，成功後才替換正式角色包：

- 最多2048個檔案。
- 解壓後最多256MB。
- 單一檔案最多32MB。
- 禁止絕對路徑、`..`與跨資料夾寫入。
- 必須包含八個必要動作及其圖片。
- 更新失敗時保留原本已安裝版本。

刪除角色包時只移除圖片與設定，角色進度會保留。若刪除的是目前角色，程式會直接
切回內建的公開角色。
