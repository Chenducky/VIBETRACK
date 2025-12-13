extends Control

# --- VibeTrack 主程式 (Square Grid Fix) ---

const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
const SUPABASE_KEY = "YOUR_ANON_KEY"
const CACHE_DIR = "user://song_cache/"
const PLAYER_POOL_SIZE: int = 10 
const RECORDING_DURATION: float = 3.0 

@onready var playlist_request: HTTPRequest = $PlaylistRequest
@onready var song_downloader: HTTPRequest = $SongDownloader
@onready var preloader: HTTPRequest = $Preloader
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var staging_slot: DraggableSample = $VBoxContainer/BottomArea/StagingSlot
@onready var record_button: Button = $"VBoxContainer/BottomArea/Record Button" 
@onready var master_play_btn: Button = $VBoxContainer/BottomArea.get_node_or_null("MasterPlayButton")
@onready var preview_ui: HBoxContainer = $VBoxContainer/BottomArea/PreviewUI
@onready var preview_play_btn: Button = $VBoxContainer/BottomArea/PreviewUI/PreviewPlayButton
@onready var confirm_btn: Button = $VBoxContainer/BottomArea/PreviewUI/ConfirmButton
@onready var cancel_btn: Button = $VBoxContainer/BottomArea/PreviewUI/CancelButton
@onready var timeline_scroll: ScrollContainer = $VBoxContainer/TracksMargin/TimelineScroll
@onready var vocal_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/Vocal_Track
@onready var rhythm_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/Rhythm_Track
@onready var sfx_track: DroppableTrackV2 = $VBoxContainer/TracksMargin/TimelineScroll/TracksArea/SFX_Track
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

enum GameMode { CAMPAIGN, PURCHASED }
var current_mode: GameMode = GameMode.CAMPAIGN
var campaign_playlist = []     
var campaign_index: int = 0    
var backup_playlist = [] 
var current_song_data = {} 
var total_chapters: int = 0      
var current_active_chapter: int = 1 
var unlocked_chapters: int = 1      
var temp_recorded_sample: AudioStreamWAV = null 
var is_playing: bool = false
var player_pool: Array[AudioStreamPlayer] = []
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null 
var is_snapping_back: bool = false

func _ready():
	print("[Main] 系統啟動...")
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, "Record")
	AudioServer.set_bus_volume_db(idx, -80.0)
	AudioServer.set_bus_mute(idx, true) 
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("song_cache"): dir.make_dir("song_cache")
	
	_init_system_components()
	_connect_signals()
	await get_tree().process_frame
	check_audio_input()
	setup_audio_bus()
	show_record_ui()
	fetch_campaign_playlist()

func _connect_signals():
	if record_button: record_button.pressed.connect(on_record_button_pressed)
	if preview_play_btn: preview_play_btn.pressed.connect(play_preview)
	if confirm_btn: confirm_btn.pressed.connect(confirm_sample)
	if cancel_btn: cancel_btn.pressed.connect(discard_sample)
	if master_play_btn: master_play_btn.pressed.connect(toggle_master_playback)
	if vocal_track: vocal_track.sample_dropped_successfully.connect(on_sample_placed)
	if rhythm_track: rhythm_track.sample_dropped_successfully.connect(on_sample_placed)
	if sfx_track: sfx_track.sample_dropped_successfully.connect(on_sample_placed)
	if playlist_request: playlist_request.request_completed.connect(_on_playlist_request_completed)
	if song_downloader: song_downloader.request_completed.connect(_on_song_downloader_completed)
	if preloader: preloader.request_completed.connect(_on_preloader_completed)

func fetch_campaign_playlist():
	status_label.text = "檢查更新中..."
	var url = SUPABASE_URL + "/rest/v1/campaign_levels?select=*&order=level_order.asc&is_active=eq.true"
	var headers = ["apikey: " + SUPABASE_KEY, "Authorization: Bearer " + SUPABASE_KEY]
	playlist_request.request(url, headers)

func _on_playlist_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json and json.size() > 0:
			campaign_playlist = []
			for item in json:
				campaign_playlist.append({ "title": item["title"], "path": item["file_url"] })
			start_campaign_mode()
		else: status_label.text = "雲端無資料"
	else: status_label.text = "連線錯誤 (%d)" % response_code

func start_campaign_mode():
	current_mode = GameMode.CAMPAIGN
	if campaign_index >= campaign_playlist.size(): campaign_index = 0
	var song = campaign_playlist[campaign_index]
	load_song(song.path, song.title)

func load_song(path_or_url: String, title: String):
	print("\n>>> 準備載入: ", title)
	status_label.text = "載入中: " + title
	stop_master_playback()
	
	if path_or_url.begins_with("http"):
		var file_name = path_or_url.md5_text() + ".mp3"
		var local_path = CACHE_DIR + file_name
		var is_cache_valid = false
		if FileAccess.file_exists(local_path):
			var f = FileAccess.open(local_path, FileAccess.READ)
			if f and f.get_length() > 0: is_cache_valid = true
			else:
				if f: f.close()
				DirAccess.remove_absolute(local_path)
		if is_cache_valid: _load_from_user_disk(local_path, title)
		else:
			status_label.text = "下載歌曲中..."
			current_song_data = { "title": title, "save_path": local_path }
			song_downloader.request(path_or_url)

func _on_song_downloader_completed(result, response_code, headers, body):
	if response_code == 200 and body.size() > 0:
		var save_path = current_song_data["save_path"]
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()
			_load_from_user_disk(save_path, current_song_data["title"])
	else:
		status_label.text = "下載失敗 (%d)" % response_code
		if current_song_data.has("save_path"):
			var p = current_song_data["save_path"]
			if FileAccess.file_exists(p): DirAccess.remove_absolute(p)

func _load_from_user_disk(path, title):
	var file = FileAccess.open(path, FileAccess.READ)
	if not file: return
	var bytes = file.get_buffer(file.get_length())
	var stream = AudioStreamMP3.new()
	stream.data = bytes
	_finish_loading_song(stream, title)

func _finish_loading_song(stream: AudioStream, title: String):
	sound_player.stream = stream
	current_song_data["title"] = title
	var raw_len = stream.get_length()
	current_song_data["duration"] = raw_len
	current_song_data["stream"] = stream
	print("歌曲就緒: %s (%.2fs)" % [title, raw_len])
	setup_song_chapters(raw_len)
	await get_tree().create_timer(0.1).timeout
	scroll_to_active_chapter()
	start_preloading_next_song()

# ==========================================
#        [核心修正] 章節計算邏輯
# ==========================================

func setup_song_chapters(seconds: float):
	# 1. 決定章節數量
	if seconds < 90: total_chapters = 2
	elif seconds < 150: total_chapters = 3
	elif seconds < 210: total_chapters = 4
	else: total_chapters = 4
	
	# 2. 計算總格數 (捨去小數點，例如 34.1格 -> 34格)
	var total_raw_grids = int(seconds / 3.0)
	
	# 3. 平分給章節 (取整數)
	# 例如 34格 / 3章 = 每章 11格 (剩下 1格變餘數)
	var grids_per_chapter = int(total_raw_grids / total_chapters)
	
	# [關鍵] "互動區" 的總時長 = 格數 * 3 * 章節數
	# 任何多出來的秒數 (包含除不盡的格數) 全部丟到尾奏
	var interactive_duration = (grids_per_chapter * 3.0) * total_chapters
	var tail_duration = seconds - interactive_duration
	
	print(">>> [修正版] 格數計算: 每章 %d 格 (正方形) | 尾奏 %.2f 秒" % [grids_per_chapter, tail_duration])
	status_label.text = "%s (每章%d格)" % [current_song_data["title"], grids_per_chapter]
	
	current_active_chapter = 1
	unlocked_chapters = 1
	
	# 將計算好的每章格數傳給音軌
	update_tracks_config(grids_per_chapter, tail_duration)

func update_tracks_config(grids: int, tail: float):
	if vocal_track: vocal_track.update_chapter_config(grids, tail, current_active_chapter, unlocked_chapters, total_chapters)
	if rhythm_track: rhythm_track.update_chapter_config(grids, tail, current_active_chapter, unlocked_chapters, total_chapters)
	if sfx_track: sfx_track.update_chapter_config(grids, tail, current_active_chapter, unlocked_chapters, total_chapters)

# ==========================================
#        播放控制
# ==========================================

func toggle_master_playback():
	if is_playing: stop_master_playback()
	else: start_master_playback()

func start_master_playback():
	if not sound_player or not sound_player.stream: return
	if sound_player.stream.get_length() < 0.1: return
	sound_player.play()
	if master_play_btn: master_play_btn.text = "⏸ 暫停"
	is_playing = true

func stop_master_playback():
	if not sound_player: return
	sound_player.stop()
	if master_play_btn: master_play_btn.text = "▶ 播放全曲"
	is_playing = false

# ==========================================
#        UI 捲動與回彈 (修正視窗判定)
# ==========================================

func _process(delta):
	# 基本防呆
	if not timeline_scroll or not vocal_track: return
	
	# 如果正在自動回彈中，就不要重複計算
	if is_snapping_back: return
	
	# 抓取音軌的單章寬度
	var chap_w = vocal_track.chapter_width
	if chap_w <= 0: return
	
	# 1. 取得當前捲動位置
	var current_scroll = timeline_scroll.scroll_horizontal
	
	# 2. [關鍵修正] 取得捲動容器的"實際顯示寬度"，而不是整個視窗寬度
	# 使用 size.x 才能扣除左右邊距 (Margin) 的影響
	var container_visible_width = timeline_scroll.size.x
	
	# 3. 計算最大捲動限制 (界線 = 已解鎖區域的右邊界)
	# 公式：(解鎖章節數 * 單章寬度) - 容器可見寬度
	# 意思就是：當"解鎖區域的右邊緣"剛好碰到"螢幕右邊緣"時，就不能再捲了
	var limit_x = (unlocked_chapters * chap_w) - container_visible_width
	
	# 防呆：如果內容比螢幕還窄，就設為 0 (不能捲動)
	var max_scroll = max(0.0, limit_x)
	
	# 4. 回彈判斷
	# 這裡我們多加 50px 的容許值，讓手感不要太死硬
	if current_scroll > max_scroll + 50:
		# 只有當滑鼠放開時才回彈 (拖曳中不干涉)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			print(">>> 超出邊界！當前: %d | 極限: %d (回彈中...)" % [current_scroll, max_scroll])
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

func start_preloading_next_song():
	if current_mode != GameMode.CAMPAIGN: return
	var next_idx = campaign_index + 1
	if next_idx >= campaign_playlist.size(): return
	var next_song = campaign_playlist[next_idx]
	var file_name = next_song.path.md5_text() + ".mp3"
	var save_path = CACHE_DIR + file_name
	if not FileAccess.file_exists(save_path):
		preloader.set_meta("save_path", save_path)
		preloader.request(next_song.path)

func _on_preloader_completed(result, response_code, headers, body):
	if response_code == 200 and body.size() > 0:
		var save_path = preloader.get_meta("save_path")
		var file = FileAccess.open(save_path, FileAccess.WRITE)
		if file:
			file.store_buffer(body)
			file.close()

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
	AudioServer.set_bus_mute(idx, true)
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
