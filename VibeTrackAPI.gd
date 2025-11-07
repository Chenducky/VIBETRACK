extends Node

## VibeTrack 14.0 溝通橋樑
## 這是「唯一」可以呼叫 SupabaseClient 的檔案。
## 我們先建立「空殼」，讓「音樂師」可以呼叫它們。

# --- 音樂師 (A) 需要的函式 ---

# 當「音樂師」拖放音軌時，會呼叫這個函式
# GDD 14.0 規格
func save_sample_to_db(audio_data: PackedByteArray, track_type: String, start_time: float, chapter: int):
	print("【VibeTrackAPI】: 收到「音樂師」的儲存請求... (尚未實作)")
	# TODO: 製作人 (B) 未來會在這裡填上 Supabase Storage 上傳 和 Database INSERT
	pass

# 當「音樂師」的播放器需要歌曲資料時，會呼叫這個函式
# [cite_start]GDD 14.0 規格 [cite: 87-88]
func get_all_samples_from_db(group_id: String) -> Array:
	print("【VibeTrackAPI】: 收到「音樂師」的讀取歌曲請求... (尚未實作)")
	# TODO: 製作人 (B) 未來會在這裡填上 Supabase SELECT * FROM song_tracks
	return [] # (重要！) 先傳回空陣列，避免「音樂師」的遊戲崩潰

# 當「音樂師」要檢查章節鎖定時，會呼叫這個函式
# [cite_start]GDD 14.0 規格 [cite: 116-117]
func get_song_progression(group_id: String) -> Dictionary:
	print("【VibeTrackAPI】: 收到「音樂師」的讀取章節請求... (尚未實作)")
	# TODO: 製作人 (B) 未來會在這裡填上 Supabase SELECT current_chapter
	return { "current_chapter": 1 } # (重要！) 先傳回假資料，避免遊戲崩潰

# --- 製作人 (B) 需要的函式 ---

# (GDD 14.0) [cite_start][cite: 102-103, 110-111, 107-108]
func get_group_economy(group_id: String) -> Dictionary:
	print("【VibeTrackAPI】: (B) 讀取群組經濟... (尚未實作)")
	# TODO: (B) 實作 SELECT xp, vibe_coins, power_tokens
	return { "xp": 0, "level": 1, "vibe_coins": 0, "power_tokens": 0 }

# (GDD 14.0) [cite_start][cite: 104-106, 107-108]
func use_power_token(user_id: String):
	print("【VibeTrackAPI】: (B) 消耗電力... (尚未實作)")
	# TODO: (B) 實作 UPDATE group_members SET power_tokens = power_tokens - 1
	pass

# (GDD 14.0) [cite_start][cite: 124-125]
func get_store_items() -> Array:
	print("【VibeTrackAPI】: (B) 讀取商店... (尚未實作)")
	# TODO: (B) 實作 SELECT * FROM store_items
	return []

# (GDD 14.0) [cite_start][cite: 126-127]
func vote_for_item(user_id: String, item_id: String):
	print("【VibeTrackAPI】: (B) 進行投票... (尚未實作)")
	# TODO: (B) 實作 INSERT INTO group_votes
	pass
