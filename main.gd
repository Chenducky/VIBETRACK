extends Control

# GDD 14.0 核心設定
const BPM: float = 120.0
const BEATS_PER_CHAPTER: int = 16 # 每個樂章有 16 拍 (4 小節)
const SECONDS_PER_BEAT: float = 60.0 / BPM
const PLAYER_POOL_SIZE: int = 10 # 音訊播放器池的大小
const RECORDING_DURATION: float = 3.0 # 3 秒錄音

# @onready 變數
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var record_button: Button = $"VBoxContainer/ControlsHBox/Record Button"
@onready var play_button: Button = $"VBoxContainer/ControlsHBox/Play Button"
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

# GDD 14.0 新 UI 節點
@onready var staging_slot: DraggableSample = $"VBoxContainer/ControlsHBox/StagingSlot"
@onready var vocal_track: DroppableTrack = $"VBoxContainer/ControlsHBox/Vocal_Track"
@onready var rhythm_track: DroppableTrack = $"VBoxContainer/ControlsHBox/Rhythm_Track"
@onready var sfx_track: DroppableTrack = $"VBoxContainer/ControlsHBox/SFX_Track"

# GDD 14.0 核心資料
var song_data: Array = [] # 從 VibeTrackAPI 獲取的歌曲資料
var recorded_sample: AudioStreamWAV = null
var is_playing: bool = false
var playback_head_time: float = 0.0 # 播放頭，單位：秒

# 播放器池
var player_pool: Array[AudioStreamPlayer] = []

# 錄音相關變數
var is_recording: bool = false
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null  # 用於錄音的播放器

func _ready():
	print("[Main] 場景開始初始化...")
	
	if not status_label:
		push_error("[Main] status_label 未找到！")
		return
	if not record_button:
		push_error("[Main] record_button 未找到！")
		return
	if not play_button:
		push_error("[Main] play_button 未找到！")
		return
	
	print("[Main] 所有 UI 節點已找到")
	
	# 初始化播放器池
	for i in PLAYER_POOL_SIZE:
		var p = AudioStreamPlayer.new()
		add_child(p)
		player_pool.append(p)
	print("[Main] 已建立 %d 個 AudioStreamPlayer 池" % PLAYER_POOL_SIZE)
	
	# 連接按鈕訊號
	record_button.pressed.connect(on_record_button_pressed)
	play_button.pressed.connect(on_play_button_pressed)
	playback_timer.timeout.connect(on_playback_timer_timeout)
	
	# 建立錄音計時器
	recording_timer = Timer.new()
	recording_timer.one_shot = true
	recording_timer.timeout.connect(_on_recording_timer_timeout)
	add_child(recording_timer)
	
	# 設定初始狀態
	status_label.text = "就緒"
	
	# 延遲檢查 Audio Input（等待一幀確保所有東西都已載入）
	await get_tree().process_frame
	check_audio_input()

	# 連接 DroppableTrack 的信號，以便在放置成功後更新 UI
	vocal_track.sample_dropped_successfully.connect(on_sample_placed)
	rhythm_track.sample_dropped_successfully.connect(on_sample_placed)
	sfx_track.sample_dropped_successfully.connect(on_sample_placed)
		
	print("[Main] 場景初始化完成")

func check_audio_input():
	# 在 Godot 4 中，我們直接使用 AudioServer 單例
	var input_devices = AudioServer.get_input_device_list()
	
	if input_devices.size() == 0:
		status_label.text = "警告：未偵測到輸入裝置"
		print("[錄音] 未偵測到輸入裝置")
	else:
		# AudioServer.input_device 仍然是獲取當前預設裝置的正確方式
		var default_input = AudioServer.input_device
		status_label.text = "就緒 (輸入裝置: %s)" % default_input
		print("[錄音] 輸入裝置數量: ", input_devices.size())
		print("[錄音] 當前輸入裝置: ", default_input)
		# 在 Godot 4 中，is_input_device_enabled() 已被移除。
		# 只要 get_input_device_list() 的數量大於 0，就代表音訊輸入是可用的。

func setup_audio_bus() -> bool:
	var audio_server = AudioServer
	var record_bus_index: int = audio_server.get_bus_index("Record")
	
	if record_bus_index == -1:
		status_label.text = "錯誤：找不到 'Record' 音訊匯流排"
		print("[錄音錯誤] Record 匯流排不存在")
		return false
	
	print("[錄音] 找到 Record 匯流排，索引: ", record_bus_index)
	
	# 建立 AudioEffectRecord
	record_effect = AudioEffectRecord.new()
	
	# 檢查是否已經有 Record effect（避免重複添加）
	var existing_effects = audio_server.get_bus_effect_count(record_bus_index)
	var has_record_effect = false
	
	for i in existing_effects:
		var effect = audio_server.get_bus_effect(record_bus_index, i)
		if effect is AudioEffectRecord:
			has_record_effect = true
			record_effect = effect
			print("[錄音] 找到現有的 AudioEffectRecord")
			break
	
	if not has_record_effect:
		audio_server.add_bus_effect(record_bus_index, record_effect, 0)
		print("[錄音] 已添加 AudioEffectRecord 到 Record 匯流排")
	
	# 建立一個 AudioStreamPlayer 連接到 Record 匯流排
	if record_player == null:
		record_player = AudioStreamPlayer.new()
		record_player.bus = "Record"
		add_child(record_player)
		print("[錄音] 已建立 Record 播放器")
	
	status_label.text = "音訊系統已就緒"
	return true

func on_record_button_pressed():
	# 延遲初始化策略
	if not is_audio_setup:
		if not setup_audio_bus():
			status_label.text = "錯誤：無法設定音訊系統"
			print("[錄音錯誤] 無法設定音訊系統")
			return
		is_audio_setup = true
	
	# 切換錄音狀態
	if is_recording:
		# 停止錄音
		stop_recording()
	else:
		# 開始錄音
		start_recording()

func start_recording():
	if record_effect == null:
		status_label.text = "錯誤：錄音系統未初始化"
		print("[錄音錯誤] record_effect 為 null")
		return
	
	print("[錄音] 開始錄音...")
	
	# 停止之前的錄音（如果有的話）
	if record_effect.is_recording_active():
		record_effect.set_recording_active(false)
		await get_tree().process_frame
	
	# 開始錄音
	record_effect.set_recording_active(true)
	
	# 確保 Record 播放器正在播放
	if record_player and not record_player.playing:
		var mic_stream = AudioStreamMicrophone.new()
		record_player.stream = mic_stream
		record_player.play()
		print("[錄音] Record 播放器已啟動")
	
	is_recording = true
	record_button.text = "停止錄音..."
	status_label.text = "正在錄音... (3秒)"
	
	# 設定 3 秒計時器自動停止
	recording_timer.wait_time = RECORDING_DURATION
	recording_timer.start()
	
	print("[錄音] 錄音狀態: ", record_effect.is_recording_active())

func stop_recording():
	if record_effect == null:
		print("[錄音錯誤] stop_recording: record_effect 為 null")
		return
	
	print("[錄音] 停止錄音...")
	
	# 停止 Record 播放器
	if record_player and record_player.playing:
		record_player.stop()
	
	# 停止錄音
	record_effect.set_recording_active(false)
	recording_timer.stop()
	
	# 等待一幀，確保錄音數據已經寫入
	await get_tree().process_frame
	
	# 獲取錄音
	recorded_sample = record_effect.get_recording()
	
	print("[錄音] 錄音數據: ", recorded_sample != null)
	
	if recorded_sample != null:
		print("[錄音] 錄音長度: ", recorded_sample.data.size(), " bytes")
		print("[錄音] 採樣率: ", recorded_sample.mix_rate, " Hz")
		print("[錄音] 格式: ", recorded_sample.format)
		
		# 限制長度為 3 秒（保險起見）
		var max_length = recorded_sample.mix_rate * RECORDING_DURATION
		if recorded_sample.data.size() > max_length:
			var trimmed_data = recorded_sample.data.slice(0, max_length)
			recorded_sample.data = trimmed_data
			print("[錄音] 已截取為 3 秒")
		
		is_recording = false
		record_button.text = "Record"
		status_label.text = "錄音完成！(3秒樣本已儲存)"
		
		# 自動播放預覽
		preview_recording()
	else:
		# 清除暫存槽 UI
		for child in staging_slot.get_children():
			child.queue_free()
			
		is_recording = false
		record_button.text = "Record"
		status_label.text = "錄音失敗：無法獲取錄音資料"
		print("[錄音錯誤] 無法獲取錄音資料")

func _on_recording_timer_timeout() -> void:
	print("[錄音] 計時器到期，自動停止")
	if is_recording:
		stop_recording()

func preview_recording():
	if recorded_sample != null:
		sound_player.stream = recorded_sample
		sound_player.play()
		status_label.text = "正在預覽錄音..."
		print("[錄音] 開始預覽")
		
		# GDD 14.0 流程：更新 StagingSlot UI，使其可被拖曳
		# 清除舊的 UI
		for child in staging_slot.get_children():
			child.queue_free()
			
		# 建立一個新的 Label 來代表這個可拖曳的樣本
		var label = Label.new()
		label.text = "錄音好了！\n拖我！"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
		# 將錄音資料交給 DraggableSample 腳本處理
		staging_slot.audio_sample = recorded_sample
		
		staging_slot.add_child(label)

func on_sample_placed():
	"""當 DroppableTrack 發出 sample_dropped_successfully 信號時，此函式會被呼叫。"""
	print("[Main] 收到音檔放置成功信號，正在清空暫存槽...")
	
	# 清空本地的錄音資料
	recorded_sample = null
	staging_slot.audio_sample = null
	
	# 重設 StagingSlot 的 UI
	for child in staging_slot.get_children():
		child.queue_free()
	
	var label = Label.new()
	label.text = "暫存槽"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	staging_slot.add_child(label)

# --- 渲染功能 ---

func render_block(block_data: Dictionary):
	# TODO: 根據 block_data 渲染一個代表音檔的 UI 元素 (例如 Panel 或 Button)
	# 並將其 add_child 到對應的 track_node 上
	pass

func render_all_tracks():
	# TODO: 清除所有音軌上的舊 UI 元素
	# for block_data in song_data:
	#     render_block(block_data)
	pass

# --- 播放功能 ---

func on_play_button_pressed():
	is_playing = !is_playing
	
	if is_playing:
		playback_head_time = 0.0
		play_button.text = "Stop"
		playback_timer.start()
		status_label.text = "播放中..."
	else:
		play_button.text = "Play"
		playback_timer.stop()
		# 停止所有在播放的聲音
		for p in player_pool:
			p.stop()
		status_label.text = "已停止播放"

func on_playback_timer_timeout():
	if not is_playing:
		return
		
	var time_since_last_frame = playback_timer.wait_time
	var next_playback_head_time = playback_head_time + time_since_last_frame
	
	# 遍歷歌曲資料，尋找需要在此幀觸發的音檔
	for sample in song_data:
		var start_time = sample.get("start_time", -1.0)
		if start_time >= playback_head_time and start_time < next_playback_head_time:
			# 找到一個需要播放的音檔
			print("[播放器] 觸發音檔，開始時間: ", start_time)
			# TODO: 這裡需要從 VibeTrackAPI 獲取已載入的 AudioStream
			# var stream = VibeTrackAPI.get_loaded_stream(sample.audio_url)
			# if stream:
			#    play_from_pool(stream)
			
	# 更新播放頭時間
	playback_head_time = next_playback_head_time
	
	# TODO: 之後加入循環播放邏輯
