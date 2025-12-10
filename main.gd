extends Control

# --- VibeTrack 主程式 ---

const PLAYER_POOL_SIZE: int = 10 
const RECORDING_DURATION: float = 3.0 

# --- 1. 節點引用 ---

# 狀態標籤
@onready var status_label: Label = $VBoxContainer/StatusLabel

# 底部操作區
@onready var staging_slot: DraggableSample = $VBoxContainer/BottomArea/StagingSlot
@onready var record_button: Button = $"VBoxContainer/BottomArea/Record Button" 

# 預覽介面
@onready var preview_ui: HBoxContainer = $VBoxContainer/BottomArea/PreviewUI
@onready var preview_play_btn: Button = $VBoxContainer/BottomArea/PreviewUI/PreviewPlayButton
@onready var confirm_btn: Button = $VBoxContainer/BottomArea/PreviewUI/ConfirmButton
@onready var cancel_btn: Button = $VBoxContainer/BottomArea/PreviewUI/CancelButton

# 音軌區 (引用 DroppableTrack)
@onready var vocal_track: DroppableTrack = $VBoxContainer/TimelineScroll/TracksArea/Vocal_Track
@onready var rhythm_track: DroppableTrack = $VBoxContainer/TimelineScroll/TracksArea/Rhythm_Track
@onready var sfx_track: DroppableTrack = $VBoxContainer/TimelineScroll/TracksArea/SFX_Track

# 音訊與計時器
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

# --- 2. 核心資料變數 ---
var temp_recorded_sample: AudioStreamWAV = null 
var is_playing: bool = false
var player_pool: Array[AudioStreamPlayer] = []

# 錄音相關
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null 

func _ready():
	print("[Main] 場景開始初始化...")
	
	# 初始化播放器池
	for i in PLAYER_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		player_pool.append(p)
	
	# 初始化錄音計時器
	recording_timer = Timer.new()
	recording_timer.one_shot = true
	recording_timer.timeout.connect(_on_recording_timer_timeout)
	add_child(recording_timer)
	
	# 連接按鈕訊號
	if record_button: record_button.pressed.connect(on_record_button_pressed)
	if preview_play_btn: preview_play_btn.pressed.connect(play_preview)
	if confirm_btn: confirm_btn.pressed.connect(confirm_sample)
	if cancel_btn: cancel_btn.pressed.connect(discard_sample)
	
	# 連接音軌訊號
	if vocal_track: vocal_track.sample_dropped_successfully.connect(on_sample_placed)
	if rhythm_track: rhythm_track.sample_dropped_successfully.connect(on_sample_placed)
	if sfx_track: sfx_track.sample_dropped_successfully.connect(on_sample_placed)
	
	# 初始化音訊
	await get_tree().process_frame
	check_audio_input()
	setup_audio_bus()

	# 初始狀態
	show_record_ui()
	
	# (新功能) 初始化章節設定：目前解鎖 2 章，正在玩第 2 章
	update_tracks_chapter_info(2, 2)

# --- 輔助：一次更新所有音軌的章節 ---
func update_tracks_chapter_info(current: int, unlocked: int):
	if vocal_track: vocal_track.update_chapter_info(current, unlocked)
	if rhythm_track: rhythm_track.update_chapter_info(current, unlocked)
	if sfx_track: sfx_track.update_chapter_info(current, unlocked)

# --- UI 狀態切換 ---
func show_record_ui():
	if record_button: record_button.visible = true
	if preview_ui: preview_ui.visible = false
	status_label.text = "就緒 (點擊錄音)"

func show_preview_ui():
	if record_button: record_button.visible = false
	if preview_ui: preview_ui.visible = true
	status_label.text = "預覽錄音 (V 確認 / X 重錄)"

# --- 音訊系統 ---
func check_audio_input():
	var input_devices = AudioServer.get_input_device_list()
	if input_devices.size() == 0:
		status_label.text = "警告：未偵測到麥克風"

func setup_audio_bus() -> bool:
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1: return false
	
	var existing_effects = AudioServer.get_bus_effect_count(idx)
	var has_effect = false
	for i in existing_effects:
		if AudioServer.get_bus_effect(idx, i) is AudioEffectRecord:
			record_effect = AudioServer.get_bus_effect(idx, i)
			has_effect = true
			break
			
	if not has_effect:
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(idx, record_effect)
	
	if record_player == null:
		record_player = AudioStreamPlayer.new()
		record_player.bus = "Record"
		record_player.stream = AudioStreamMicrophone.new()
		add_child(record_player)
		record_player.play()
		
	is_audio_setup = true
	return true

# --- 錄音邏輯 ---
func on_record_button_pressed():
	if not is_audio_setup: setup_audio_bus()
	if not record_effect: return

	if record_effect.is_recording_active():
		stop_recording()
	else:
		start_recording()

func start_recording():
	if not record_effect: return
	if record_effect.is_recording_active(): record_effect.set_recording_active(false)
	
	record_effect.set_recording_active(true)
	recording_timer.start(RECORDING_DURATION)
	
	record_button.text = "..."
	record_button.disabled = true
	status_label.text = "正在錄製..."

func _on_recording_timer_timeout():
	stop_recording()

func stop_recording():
	if not record_effect: return
	record_effect.set_recording_active(false)
	record_button.text = "R"
	record_button.disabled = false
	
	temp_recorded_sample = record_effect.get_recording()
	
	if temp_recorded_sample:
		show_preview_ui()
		play_preview()
	else:
		show_record_ui()

# --- 預覽與確認 ---
func play_preview():
	if temp_recorded_sample:
		sound_player.stream = temp_recorded_sample
		sound_player.play()

func discard_sample():
	temp_recorded_sample = null
	show_record_ui()

func confirm_sample():
	if staging_slot and staging_slot.has_method("set_sample"):
		staging_slot.set_sample(temp_recorded_sample)
	
	temp_recorded_sample = null
	show_record_ui()
	status_label.text = "音檔已入槽！"

func on_sample_placed(_data):
	if staging_slot and staging_slot.has_method("clear_sample"):
		staging_slot.clear_sample()
