# Vibe Track - Project Bible (Technical Context)

## 1. 專案概觀
- **引擎**: Godot 4.x (GDScript 2.0)
- **後端**: Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **目標平台**: iOS (App Store)
- **核心玩法**: 2-5人好友群組，錄製環境噪音(Samples)，在共享音軌上共同創作 Lo-fi 音樂。

## 2. 核心代碼規範 (Strict Rules)
- **使用 GDScript 2.0**: 必須使用 `@export`, `super()`, `await` 等新語法。
- **強型別**: 盡可能宣告變數類型，例如 `var vibe_coins: int = 0`。
- **註解風格**: 所有複雜邏輯必須包含繁體中文註解。
- **UI 與邏輯分離**: 邏輯寫在 `.gd`，UI 節點引用使用 `@onready` 或 Unique Name (`%LabelName`)。

## 3. 資料庫結構 (Supabase Schema) - *AI 必須嚴格遵守*
- **users 表**: `id` (uuid), `username` (text), `power_tokens` (int, 電力)
- **groups 表**: `id` (uuid), `group_code` (text), `vibe_coins` (int, 群組幣), `xp` (int), `level` (int)
- **song_tracks 表**:
  - `track_type`: enum('vocal', 'rhythm', 'sfx')
  - `start_time`: float (秒)
  - `audio_url`: text (Supabase Storage URL)
  - `created_by`: uuid (user_id)

## 4. 全域單例 (Global Singletons)
- `GameManager.gd` (Autoload 名稱: `GameManager`):
  - 負責管理 `current_user_data`, `current_group_data`。
  - 負責處理 XP 增加 (`add_group_xp`) 和 貨幣扣除。
- `Network.gd` (Autoload 名稱: `Network`):
  - 負責所有 `Supabase` 的 HTTP 請求。

## 5. 關鍵機制 (這就是我們正在做的)
- **錄音 CD**: 15分鐘冷卻。使用 `Timer` 節點。可用 `power_tokens` 跳過。
- **拖曳機制**: `_get_drag_data` (來源) 和 `_drop_data` (目標)。
- **音軌邏輯**:
  - 'vocal'/'rhythm': GridContainer (格子狀)
  - 'sfx': Control (自由時間軸，允許重疊)

## 6. 給 AI 的指令
- 當你編寫代碼時，必須檢查是否符合上述資料結構。
- 如果需要使用 Supabase，請使用 `godot-supabase` 插件的語法風格。
- 始終假設使用者是初學者，提供「如何連接節點」的步驟說明。
