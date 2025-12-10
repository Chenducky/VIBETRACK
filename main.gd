extends Control

# --- VibeTrack 主程式 (Ultimate Stable Edition) ---

# [必填] 請填入您的 Supabase 資訊
const SUPABASE_URL = "https://xypsjytjvzgubvbzjzag.supabase.co/"
const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5cHNqeXRqdnpndWJ2YnpqemFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIwMjM5NjQsImV4cCI6MjA3NzU5OTk2NH0.dWzJUv3bEjAb5SUMi_ARpQTd5HDDl95vDCmU80F6e4A"

# [設定] 快取資料夾路徑
const CACHE_DIR = "user://song_cache/"

const PLAYER_POOL_SIZE: int = 10 
const RECORDING_DURATION: float = 3.0 

# --- 1. 節點引用 ---

# 網路連線節點 (請確保場景中有這三個節點)
@onready var playlist_request: HTTPRequest = $PlaylistRequest
@onready var song_downloader: HTTPRequest = $SongDownloader
@onready var preloader: HTTPRequest = $Preloader

# 介面節點
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var staging_slot: DraggableSample = $VBoxContainer/BottomArea/StagingSlot
@onready var record_button: Button = $"VBoxContainer/BottomArea/Record Button" 

# [防呆] 使用 get_node_or_null 防止找不到按鈕時崩潰
@onready var master_play_btn: Button = $VBoxContainer/BottomArea.get_node_or_null("MasterPlayButton")

# 預覽介面
@onready var preview_ui: HBoxContainer = $VBoxContainer/BottomArea/PreviewUI
@onready var preview_play_btn: Button = $VBoxContainer/BottomArea/PreviewUI/PreviewPlayButton
@onready var confirm_btn: Button = $VBoxContainer/BottomArea/PreviewUI/ConfirmButton
@onready var cancel_btn: Button = $VBoxContainer/BottomArea/PreviewUI/CancelButton

# 音軌區 (使用 V2 版)
# 請確認您的場景結構是否包含 TracksMargin，若無請調整路徑
@onready var timeline_scroll: ScrollContainer = $VBoxContainer/TracksMargin/TimelineScroll
@onready var vocal_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/Vocal_Track
@onready var rhythm_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/Rhythm_Track
@onready var sfx_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/SFX_Track

# 音訊與計時器
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

# --- 2. 核心資料 ---

# 遊戲模式
enum GameMode { CAMPAIGN, PURCHASED }
var current_mode: GameMode = GameMode.CAMPAIGN

# 歌單管理
var campaign_playlist = []     # 從雲端抓下來的主線清單
var campaign_index: int = 0    # 目前玩到第幾關

# [備用] 離線歌單 (請確保 res:// 路徑正確)
var backup_playlist = [
	{ "title": "離線教學曲", "path": "res://music/song_short.mp3" } 
]

# 當前歌曲狀態
var current_song_data = {} 
var total_chapters: int = 0      
var current_active_chapter: int = 1 
var unlocked_chapters: int = 1      

# 錄音系統變數
var temp_recorded_sample: AudioStreamWAV = null 
var is_playing: bool = false
var player_pool: Array[AudioStreamPlayer] = []
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null 

# 回彈動畫控制
var is_snapping_back: bool = false

# ==========================================
#        初始化流程
# ==========================================

func _ready():
	print("[Main] 系統啟動...")
	
	# --- [噪音殺手] 強制初始化並靜音錄音通道 ---
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, "Record")
	
	# 關鍵：將錄音通道的音量設為 0，並開啟靜音
	AudioServer.set_bus_volume_db(idx, -80.0) 
	AudioServer.set_bus_mute(idx, true) 
	print("[系統] 錄音通道已強制靜音 (噪音消除)")
	# ----------------------------------------

	# 建立快取資料夾
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("song_cache"):
		dir.make_dir("song_cache")
	
	# 2. 初始化系統元件
	_init_system_components()
	_connect_signals()
	
	# 3. 初始化音訊
	await get_tree().process_frame
	check_audio_input()
	setup_audio_bus()
	show_record_ui()
	
	# 4. 啟動：抓取雲端歌單
	fetch_campaign_playlist()

func _connect_signals():
	if record_button: record_button.pressed.connect(on_record_button_pressed)
	if preview_play_btn: preview_play_btn.pressed.connect(play_preview)
	if confirm_btn: confirm_btn.pressed.connect(confirm_sample)
	if cancel_btn: cancel_btn.pressed.connect(discard_sample)
	
	# [安全連接] 全曲播放按鈕
	if master_play_btn:
		master_play_btn.pressed.connect(toggle_master_playback)
	
	if vocal_track: vocal_track.sample_dropped_successfully.connect(on_sample_placed)
	if rhythm_track: rhythm_track.sample_dropped_successfully.connect(on_sample_placed)
	if sfx_track: sfx_track.sample_dropped_successfully.connect(on_sample_placed)
	
	# 網路訊號
	if playlist_request: playlist_request.request_completed.connect(_on_playlist_request_completed)
	if song_downloader: song_downloader.request_completed.connect(_on_song_downloader_completed)
	if preloader: preloader.request_completed.connect(_on_preloader_completed)

# ==========================================
#        [階段一] 歌單管理 (雲端/離線)
# ==========================================

func fetch_campaign_playlist():
	print("正在連線雲端歌單...")
	status_label.text = "檢查更新中..."
	
	var url = SUPABASE_URL + "/rest/v1/campaign_levels?select=*&order=level_order.asc&is_active=eq.true"
	var headers = ["apikey: " + SUPABASE_KEY, "Authorization: Bearer " + SUPABASE_KEY]
	
	var err = playlist_request.request(url, headers)
	if err != OK:
		print("請求發送失敗，切換離線模式")
		use_offline_playlist()

func _on_playlist_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.size() > 0:
			print("歌單更新成功！共 %d 關" % json.size())
			campaign_playlist = []
			for item in json:
				campaign_playlist.append({ "title": item["title"], "path": item["file_url"] })
			
			start_campaign_mode() # 開始第一關
		else:
			use_offline_playlist()
	else:
		print("連線錯誤 (%d)，切換離線模式" % response_code)
		use_offline_playlist()

func use_offline_playlist():
	print("使用離線備用歌單")
	campaign_playlist = backup_playlist.duplicate()
	start_campaign_mode()

func start_campaign_mode():
	current_mode = GameMode.CAMPAIGN
	if campaign_index >= campaign_playlist.size(): campaign_index = 0
	
	var song = campaign_playlist[campaign_index]
	load_song(song.path, song.title)

# ==========================================
#        [階段二] 歌曲載入 (安全快取/MD5/壞檔檢查)
# ==========================================

func load_song(path_or_url: String, title: String):
	print("\n>>> 準備載入: ", title)
	status_label.text = "載入中: " + title
	
	stop_master_playback() # 停止當前播放
	
	# 1. 本地資源 (res://)
	if path_or_url.begins_with("res://"):
		if FileAccess.file_exists(path_or_url):
			_finish_loading_song(load(path_or_url), title)
		else:
			status_label.text = "錯誤：找不到本地檔案"
		return

	# 2. 雲端資源 (http)
	if path_or_url.begins_with("http"):
		# [關鍵] 使用 MD5 雜湊檔名，避免特殊字元導致存檔失敗
		var file_name = path_or_url.md5_text() + ".mp3"
		var local_path = CACHE_DIR + file_name
		
		# [關鍵] 檢查快取是否有效 (大於 0KB)
		var is_cache_valid = false
		if FileAccess.file_exists(local_path):
			var f = FileAccess.open(local_path, FileAccess.READ)
			if f and f.get_length() > 0:
				is_cache_valid = true
			else:
				print("[系統] 發現壞檔 (0KB)，刪除重抓...")
				if f: f.close()
				DirAccess.remove_absolute(local_path)
		
		if is_cache_valid:
			print("[快取命中] 直接讀取: ", file_name)
			_load_from_user_disk(local_path, title)
		else:
			print("[雲端下載] 開始下載: ", title)
			status_label.text = "下載歌曲中..."
			current_song_data = { "title": title, "save_path": local_path }
			song_downloader.request(path_or_url)

func _on_song_downloader_completed(result, response_code, headers, body):
	# [關鍵] 嚴格檢查：HTTP 200 且 內容不為空
	if response_code == 200 and body.size() > 0:
		print("下載成功，大小: %d bytes" % body.size())
		var save_path = current_song_data["save_path"]
		
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			_load_from_user_disk(save_path, current_song_data["title"])
		else:
			status_label.text = "存檔失敗 (權限錯誤)"
	else:
		status_label.text = "下載失敗 (%d)" % response_code
		# 清除可能的殘留壞檔
		if current_song_data.has("save_path"):
			var p = current_song_data["save_path"]
			if FileAccess.file_exists(p): DirAccess.remove_absolute(p)

func _load_from_user_disk(path, title):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[錯誤] 無法開啟快取檔案")
		# 嘗試刪除壞檔
		DirAccess.remove_absolute(path)
		status_label.text = "檔案損毀，請重試"
		return

	var bytes = file.get_buffer(file.get_length())
	var stream = AudioStreamMP3.new()
	stream.data = bytes
	_finish_loading_song(stream, title)

# ==========================================
#        [階段三] 歌曲就緒與背景預載
# ==========================================

func _finish_loading_song(stream: AudioStream, title: String):
	sound_player.stream = stream
	current_song_data["title"] = title
	# 防呆：確保長度至少為 1
	var raw_len = stream.get_length()
	current_song_data["duration"] = int(raw_len) if raw_len > 0 else 1
	current_song_data["stream"] = stream
	
	print("歌曲就緒: %s (%ds)" % [title, current_song_data["duration"]])
	
	# 1. 計算章節
	setup_song_chapters(current_song_data["duration"])
	
	# 2. 自動捲動
	await get_tree().create_timer(0.1).timeout
	scroll_to_active_chapter()
	
	# 3. 預載下一首
	start_preloading_next_song()

func start_preloading_next_song():
	if current_mode != GameMode.CAMPAIGN: return
	var next_idx = campaign_index + 1
	if next_idx >= campaign_playlist.size(): return
	
	var next_song = campaign_playlist[next_idx]
	var next_url = next_song.path
	if next_url.begins_with("res://"): return
	
	# 使用相同的 MD5 命名規則
	var file_name = next_url.md5_text() + ".mp3"
	var save_path = CACHE_DIR + file_name
	
	# 檢查是否需要下載
	if not FileAccess.file_exists(save_path):
		print("[預載] 背景下載下一首...")
		preloader.set_meta("save_path", save_path)
		preloader.request(next_url)
	else:
		# 簡單檢查大小
		var f = FileAccess.open(save_path, FileAccess.READ)
		if f and f.get_length() == 0:
			f.close()
			DirAccess.remove_absolute(save_path)
			print("[預載] 發現舊壞檔，重新下載...")
			preloader.set_meta("save_path", save_path)
			preloader.request(next_url)

func _on_preloader_completed(result, response_code, headers, body):
	if response_code == 200 and body.size() > 0:
		var save_path = preloader.get_meta("save_path")
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			print("[預載] 成功存檔")

# ==========================================
#        [核心] 全曲播放控制 (修復版)
# ==========================================

# ==========================================
#        [核心] 全曲播放控制 (縮排修復版)
# ==========================================

func toggle_master_playback():
	if is_playing:
		stop_master_playback()
	else:
		start_master_playback()

func start_master_playback():
	# 1. 檢查 SoundPlayer
	if not sound_player: return
	
	# 2. 檢查音檔是否存在
	if not sound_player.stream: 
		print("[播放失敗] 沒有音訊來源")
		return

	# 3. 檢查音檔是否損毀 (長度過短通常是壞檔)
	if sound_player.stream.get_length() < 0.1:
		print("[播放失敗] 音訊長度異常 (可能是壞檔)，拒絕播放")
		status_label.text = "音檔損毀，請重啟"
		return

	# 4. 播放
	sound_player.play()
	
	# 5. 更新按鈕與狀態
	if master_play_btn: 
		master_play_btn.text = "⏸ 暫停"
	
	is_playing = true

func stop_master_playback():
	if not sound_player: return
	
	sound_player.stop()
	
	if master_play_btn: 
		master_play_btn.text = "▶ 播放全曲"
	
	is_playing = false

# ==========================================
#        章節計算邏輯
# ==========================================

func setup_song_chapters(seconds: int):
	if seconds < 90: total_chapters = 2
	elif seconds < 150: total_chapters = 3
	elif seconds < 210: total_chapters = 4
	else: total_chapters = 4
	
	var seconds_per_chapter = int(seconds / total_chapters)
	var grids_per_chapter = int(seconds_per_chapter / 3.0)
	var tail_buffer = seconds_per_chapter % 3
	
	status_label.text = "%s (%ds)" % [current_song_data["title"], seconds]
	
	# 這裡假設新歌都是從頭開始 (您可之後加入進度讀取邏輯)
	current_active_chapter = 1
	unlocked_chapters = 1
	
	update_tracks_config(grids_per_chapter, tail_buffer, seconds_per_chapter)

# [修復] 參數數量正確 (6個)
func update_tracks_config(grids: int, tail: int, sec_per_chap: int):
	if vocal_track: vocal_track.update_chapter_config(grids, tail, sec_per_chap, current_active_chapter, unlocked_chapters, total_chapters)
	if rhythm_track: rhythm_track.update_chapter_config(grids, tail, sec_per_chap, current_active_chapter, unlocked_chapters, total_chapters)
	if sfx_track: sfx_track.update_chapter_config(grids, tail, sec_per_chap, current_active_chapter, unlocked_chapters, total_chapters)

# ==========================================
#        UI 捲動與回彈
# ==========================================

func _process(delta):
	if not timeline_scroll or not vocal_track: return
	if is_snapping_back: return
	var chap_w = vocal_track.chapter_width
	if chap_w <= 0: return
	
	var current_scroll = timeline_scroll.scroll_horizontal
	var viewport_w = timeline_scroll.get_viewport_rect().size.x
	var max_scroll = max(0.0, (unlocked_chapters * chap_w) - viewport_w)
	
	if current_scroll > max_scroll + 50:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			snap_back_to_limit(max_scroll)

func snap_back_to_limit(target_x):
	is_snapping_back = true
	var tween = create_tween()
	tween.tween_property(timeline_scroll, "scroll_horizontal", target_x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func(): is_snapping_back = false)

func scroll_to_active_chapter():
	if not vocal_track or not timeline_scroll: return
	var target_x = (current_active_chapter - 1) * vocal_track.chapter_width
	var tween = create_tween()
	tween.tween_property(timeline_scroll, "scroll_horizontal", target_x, 0.5).set_trans(Tween.TRANS_CUBIC)

# ==========================================
#        標準元件 setup
# ==========================================

func _init_system_components():
	for i in PLAYER_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		player_pool.append(p)
	recording_timer = Timer.new()
	recording_timer.one_shot = true
	recording_timer.timeout.connect(_on_recording_timer_timeout)
	add_child(recording_timer)

func show_record_ui():
	if record_button: record_button.visible = true
	if preview_ui: preview_ui.visible = false

func show_preview_ui():
	if record_button: record_button.visible = false
	if preview_ui: preview_ui.visible = true

func check_audio_input():
	if AudioServer.get_input_device_list().size() == 0: status_label.text = "警告：無麥克風"

func setup_audio_bus() -> bool:
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1: return false
	var has_effect = false
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectRecord:
			record_effect = AudioServer.get_bus_effect(idx, i)
			has_effect = true; break
	if not has_effect:
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(idx, record_effect)
	if not record_player:
		record_player = AudioStreamPlayer.new()
		record_player.bus = "Record"
		record_player.stream = AudioStreamMicrophone.new()
		add_child(record_player)
		record_player.play()
	is_audio_setup = true
	return true

func on_record_button_pressed():
	if not is_audio_setup: setup_audio_bus()
	if not record_effect: return
	if record_effect.is_recording_active(): stop_recording()
	else: start_recording()

func start_recording():
	if not record_effect: return
	record_effect.set_recording_active(true)
	recording_timer.start(RECORDING_DURATION)
	record_button.text = "..."
	record_button.disabled = true
	status_label.text = "錄製中..."

func _on_recording_timer_timeout(): stop_recording()

func stop_recording():
	if not record_effect: return
	record_effect.set_recording_active(false)
	record_button.text = "R"
	record_button.disabled = false
	temp_recorded_sample = record_effect.get_recording()
	if temp_recorded_sample: show_preview_ui(); play_preview()
	else: show_record_ui()

func play_preview():
	if temp_recorded_sample: sound_player.stream = temp_recorded_sample; sound_player.play()

func discard_sample(): temp_recorded_sample = null; show_record_ui()

func confirm_sample():
	if staging_slot and staging_slot.has_method("set_sample"): staging_slot.set_sample(temp_recorded_sample)
	temp_recorded_sample = null; show_record_ui(); status_label.text = "音檔已入槽"

func on_sample_placed(_data): if staging_slot: staging_slot.clear_sample()
