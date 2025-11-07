extends Node

## VibeTrack 14.0 溝通橋樑
## 這是「唯一」可以呼叫 SupabaseClient 的檔案。
## 我們先建立「空殼」，讓「音樂師」可以呼叫它們。

# --- 音樂師 (A) 需要的函式 ---

# 當「音樂師」拖放音軌時，會呼叫這個函式
# GDD 14.0 規格
func save_sample_to_db(audio_data: PackedByteArray, track_type: String, start_time: float, chapter: int, group_id: String) -> void:
	print("【VibeTrackAPI】: 收到「音樂師」的儲存請求，類型: %s, 時間: %s" % [track_type, start_time])

	# --- 步驟 1: 獲取 User ID 並檢查參數 ---
	var user = SupabaseClient.supabase.auth.get_user()
	if user == null:
		print("【VibeTrackAPI 錯誤】: 使用者未登入，無法儲存音檔。")
		return
	var user_id = user.id
	
	if group_id.is_empty():
		print("【VibeTrackAPI 錯誤】: group_id 為空，無法儲存。")
		return

	# --- 步驟 2: (GDD 14.0 Storage) 上傳音檔到 Supabase Storage ---
	# 建立一個唯一的檔案路徑，避免檔案名稱衝突
	var file_path = "%s/%s.wav" % [group_id, str(Time.get_unix_time_from_system())]
	print("【VibeTrackAPI】: 正在上傳音檔到 Storage: ", file_path)
	
	# 執行上傳任務
	var storage_task = SupabaseClient.supabase.storage().from("samples").upload(file_path, audio_data, {"content-type": "audio/wav"})
	await storage_task.completed

	if storage_task.error:
		print("【VibeTrackAPI 錯誤】: 上傳 Storage 失敗: ", storage_task.error)
		return

	# --- 步驟 3: (GDD 14.0 Database) 將音檔資訊寫入 'song_tracks' 資料表 ---
	var audio_url = SupabaseClient.supabase.storage().from("samples").get_public_url(file_path)
	print("【VibeTrackAPI】: 音檔 URL: %s, 正在寫入資料庫..." % audio_url)
	
	var insert_data = {
		"group_id": group_id,
		"user_id": user_id,
		"track_type": track_type,
		"start_time": start_time,
		"audio_url": audio_url,
		"chapter": chapter
	}
	var insert_task = SupabaseClient.supabase.database().query("song_tracks", "insert", insert_data)
	await insert_task.completed

	if insert_task.error:
		print("【VibeTrackAPI 錯誤】: 寫入 song_tracks 資料表失敗: ", insert_task.error)
	else:
		print("【VibeTrackAPI】: 成功！音檔已儲存並記錄到資料庫。")

# 當「音樂師」的播放器需要歌曲資料時，會呼叫這個函式
# [cite_start]GDD 14.0 規格 [cite: 87-88]
func get_all_samples_from_db(group_id: String) -> Array:
	print("【VibeTrackAPI】: 收到「音樂師」的讀取歌曲請求... (尚未實作)")
	# TODO: 製作人 (B) 未來會在這裡填上 Supabase SELECT * FROM song_tracks
	
	# 建立一個非同步任務來執行資料庫查詢
	var query_task = SupabaseClient.supabase.database().query(
		"song_tracks", 
		"select", 
		{ "select": "*", "group_id": "eq.%s" % group_id }
	)
	await query_task.completed
	
	if query_task.error:
		print("【VibeTrackAPI】錯誤：讀取 song_tracks 資料表失敗: ", query_task.error)
		return [] # 發生錯誤時，回傳空陣列以保護遊戲
	
	print("【VibeTrackAPI】: 成功讀取到 %d 筆音軌資料。" % query_task.result.size())
	return query_task.result # 將查詢結果 (一個 Array[Dictionary]) 直接回傳給「音樂師」

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
