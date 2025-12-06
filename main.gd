extends Control

# --- VibeTrack 14.0 核心設定 ---
const PLAYER_POOL_SIZE: int = 10 
const RECORDING_DURATION: float = 3.0 

# --- 1. 節點引用 (依照截圖 3.38.39 的結構) ---

# 狀態標籤
@onready var status_label: Label = $VBoxContainer/StatusLabel

# 底部操作區 (BottomArea)
# 注意：StagingSlot 應該掛載了 DraggableSample.gd
@onready var staging_slot: DraggableSample = $VBoxContainer/BottomArea/StagingSlot
# 注意：這裡對應您場景中有名稱帶空白的節點 "Record Button"
@onready var record_button: Button = $"VBoxContainer/BottomArea/Record Button" 

# 預覽介面 (PreviewUI)
@onready var preview_ui: HBoxContainer = $VBoxContainer/BottomArea/PreviewUI
@onready var preview_play_btn: Button = $VBoxContainer/BottomArea/PreviewUI/PreviewPlayButton
@onready var confirm_btn: Button = $VBoxContainer/BottomArea/PreviewUI/ConfirmButton
@onready var cancel_btn: Button = $VBoxContainer/BottomArea/PreviewUI/CancelButton

# 音軌區 (TracksArea)
# 注意：這些節點應該掛載了 DroppableTrack.gd
@onready var vocal_track: DroppableTrack = $VBoxContainer/TracksArea/Vocal_Track
@onready var rhythm_track: DroppableTrack = $VBoxContainer/TracksArea/Rhythm_Track
@onready var sfx_track: DroppableTrack = $VBoxContainer/TracksArea/SFX_Track

# 音訊與計時器
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

# --- 2. 核心資料變數 ---
var temp_recorded_sample: AudioStreamWAV = null # 暫存錄音 (還沒按確認前的)
var is_playing: bool = false

# 播放器池
var player_pool: Array[AudioStreamPlayer] = []

# 錄音相關變數
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null 

func _ready():
	print("[Main] 場景開始初始化...")
	
	# 1. 檢查必要節點是否存在 (防呆)
	if not status_label: push_error("StatusLabel 未找到")
	if not record_button: push_error("Record Button 未找到")
	if not staging_slot: push_error("StagingSlot 未找到")
	if not preview_ui: push_error("PreviewUI 未找到")
	
	# 2. 初始化播放器池 (之後播放多軌用)
	for i in PLAYER_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		player_pool.append(p)
	
	# 3. 初始化錄音計時器
	recording_timer = Timer.new()
	recording_timer.one_shot = true
	recording_timer.timeout.connect(_on_recording_timer_timeout)
	add_child(recording_timer)
	
	# 4. 連接按鈕訊號
	if record_button:
		record_button.pressed.connect(on_record_button_pressed)
	
	if preview_play_btn: preview_play_btn.pressed.connect(play_preview)
	if confirm_btn: confirm_btn.pressed.connect(confirm_sample)
	if cancel_btn: cancel_btn.pressed.connect(discard_sample)
	
	# 5. 連接音軌放置訊號 (當音檔被拖到音軌時觸發)
	# 這樣我們可以清空暫存槽，準備下一次錄音
	if vocal_track: vocal_track.sample_dropped_successfully.connect(on_sample_placed)
	if rhythm_track: rhythm_track.sample_dropped_successfully.connect(on_sample_placed)
	if sfx_track: sfx_track.sample_dropped_successfully.connect(on_sample_placed)
	
	# 6. 音訊系統初始化 (延遲一幀確保系統就緒)
	await get_tree().process_frame
	check_audio_input()
	setup_audio_bus()

	# 初始狀態：隱藏預覽，顯示錄音介面
	show_record_ui()
	print("[Main] 初始化完成")

# --- UI 狀態切換 ---

func show_record_ui():
	if record_button: record_button.visible = true
	if preview_ui: preview_ui.visible = false
	status_label.text = "就緒 (點擊錄音)"

func show_preview_ui():
	if record_button: record_button.visible = false
	if preview_ui: preview_ui.visible = true
	status_label.text = "預覽錄音 (V 確認 / X 重錄)"

# --- 音訊系統設定 ---

func check_audio_input():
	var input_devices = AudioServer.get_input_device_list()
	if input_devices.size() == 0:
		status_label.text = "警告：未偵測到麥克風"
	else:
		print("當前輸入裝置: ", AudioServer.input_device)

func setup_audio_bus() -> bool:
	var idx = AudioServer.get_bus_index("Record")
	if idx == -1:
		print("錯誤：找不到 Record 匯流排")
		status_label.text = "系統錯誤：無 Record 匯流排"
		return false
	
	# 檢查是否已有 Effect，沒有才新增
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
	
	# 確保有一個播放器連接到 Record 匯流排 (為了驅動麥克風)
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
	print("[測試] 錄音按鈕被點擊")
	if not is_audio_setup: 
		if not setup_audio_bus(): return
	
	if not record_effect:
		print("[錯誤] record_effect 為 null")
		return

	if record_effect.is_recording_active():
		stop_recording()
	else:
		start_recording()

func start_recording():
	if not record_effect: return
	
	# 清除舊的錄音狀態
	if record_effect.is_recording_active():
		record_effect.set_recording_active(false)
	
	record_effect.set_recording_active(true)
	recording_timer.start(RECORDING_DURATION)
	
	record_button.text = "..." # 錄音中
	record_button.disabled = true # 錄音期間鎖定按鈕
	status_label.text = "正在錄製 Vibe... (3秒)"

func _on_recording_timer_timeout():
	stop_recording()

func stop_recording():
	if not record_effect: return
	
	record_effect.set_recording_active(false)
	record_button.text = "R" # 或者還原成錄音圖示
	record_button.disabled = false
	
	# 獲取錄音
	temp_recorded_sample = record_effect.get_recording()
	
	if temp_recorded_sample:
		print("錄音完成，進入預覽模式")
		show_preview_ui()
		play_preview() # 自動播放一次
	else:
		status_label.text = "錄音失敗 (無數據)"
		show_record_ui()

# --- 預覽與確認流程 ---

func play_preview():
	if temp_recorded_sample:
		sound_player.stream = temp_recorded_sample
		sound_player.play()

func discard_sample():
	print("放棄錄音")
	temp_recorded_sample = null
	show_record_ui()

func confirm_sample():
	print("確認錄音！放入暫存槽")
	
	# 將錄音交給 StagingSlot (DraggableSample.gd)
	# 這裡使用 duck typing (檢查有沒有這個方法) 防止報錯
	if staging_slot and staging_slot.has_method("set_sample"):
		staging_slot.set_sample(temp_recorded_sample)
	else:
		print("[錯誤] StagingSlot 沒有 set_sample 方法，請檢查腳本掛載")
	
	temp_recorded_sample = null
	show_record_ui()
	status_label.text = "音檔已入槽，請拖曳到音軌！"

# --- 音軌放置回饋 ---

func on_sample_placed(_data):
	"""當音檔成功拖到 DroppableTrack 後觸發"""
	print("音檔已放置，清空暫存槽")
	if staging_slot and staging_slot.has_method("clear_sample"):
		staging_slot.clear_sample()
