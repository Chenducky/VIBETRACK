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
@onready var staging_slot: Panel = $VBoxContainer/ControlsHBox/StagingSlot
@onready var vocal_track: GridContainer = $VBoxContainer/VocalTrack
@onready var rhythm_track: GridContainer = $VBoxContainer/RhythmTrack
@onready var sfx_track: Control = $VBoxContainer/SfxTrack

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
	
	# 連接拖放訊號
	staging_slot.gui_input.connect(_on_staging_slot_gui_input) # 拖曳的起點仍然需要 gui_input
	
	print("[Main] 場景初始化完成")

func check_audio_input():
	var audio_server = AudioServer
	var input_device_count = audio_server.get_input_device_count()
	
	if input_device_count == 0:
		status_label.text = "警告：未偵測到輸入裝置"
		print("[錄音] 未偵測到輸入裝置")
	else:
		var default_input = audio_server.input_device
		status_label.text = "就緒 (輸入裝置: %s)" % default_input
		print("[錄音] 輸入裝置數量: ", input_device_count)
		print("[錄音] 當前輸入裝置: ", default_input)
		print("[錄音] Audio Input 啟用狀態: ", audio_server.is_input_device_enabled())

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

func _on_recording_timer_timeout():
	print("[錄音] 計時器到期，自動停止")
	if is_recording:
		stop_recording()

func preview_recording():
	if recorded_sample != null:
		sound_player.stream = recorded_sample
		sound_player.play()
		status_label.text = "正在預覽錄音..."
		print("[錄音] 開始預覽")
		
		# 更新 StagingSlot UI
		# 清除舊的 UI
		for child in staging_slot.get_children():
			child.queue_free()
		# 建立新的 Label
		var label = Label.new()
		label.text = "錄音好了！\n拖我！"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		staging_slot.add_child(label)

# --- 拖放功能 (Drag and Drop) ---

func _on_staging_slot_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if recorded_sample:
			print("[拖放] 開始從暫存槽拖曳...")
			var drag_data = {
				"type": "audio_sample",
				"sample": recorded_sample
			}
			var preview = Label.new()
			preview.text = "♪"
			set_drag_preview(preview)
			# 在 Godot 4 中，我們使用 drag_and_drop 來啟動
			drag_and_drop(drag_data, preview)

func _can_drop_data(_at_position: Vector2, data) -> bool:
	# 檢查拖曳過來的資料是否是我們能接受的 "audio_sample" 類型
	return data is Dictionary and data.get("type") == "audio_sample"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# Godot 會自動偵測滑鼠在哪個 Control 上方，我們用 get_focus_owner() 來取得它
	var track_node = get_focus_owner()
	if not (track_node in [vocal_track, rhythm_track, sfx_track]):
		print("[拖放] 放置在無效的區域")
		return
		
	# 呼叫我們原本的放置邏輯，但現在是從 Godot 的 _drop_data 函式中觸發
	_on_drop_data(track_node, data, at_position)

func _on_drop_data(track_node: Control, data: Dictionary, position: Vector2):
	print("[拖放] 在 %s 上偵測到放置事件" % track_node.name)
	
	var track_type: String
	var start_time: float
	var chapter: int = 1 # TODO: 之後從 get_song_progression 取得
	
	# 根據音軌類型決定 start_time 計算方式
	match track_node.name:
		"VocalTrack", "RhythmTrack":
			track_type = "vocal" if track_node.name == "VocalTrack" else "rhythm"
			# GridContainer: 對齊到網格
			var grid_size = track_node.size / track_node.columns
			var column = int(position.x / grid_size.x)
			start_time = column * SECONDS_PER_BEAT
			
		"SfxTrack":
			track_type = "sfx"
			# Control: 自由時間軸
			var total_width = track_node.size.x
			var total_duration = BEATS_PER_CHAPTER * SECONDS_PER_BEAT # TODO: 之後要乘以總章節數
			start_time = (position.x / total_width) * total_duration
			
		_:
			print("[拖放] 錯誤：未知的音軌類型")
			return
			
	print("[拖放] 計算結果 -> track_type: %s, start_time: %.2f" % [track_type, start_time])
	
	# GDD 14.0 黃金定律：呼叫 API 進行儲存
	if data.sample and data.sample.data:
		VibeTrackAPI.save_sample_to_db(data.sample.data, track_type, start_time, chapter)
		
		# 樂觀更新 UI (Optimistic UI Update)
		# 假設儲存會成功，立即在本地渲染一個假的音檔塊
		var temp_block_data = {
			"track_type": track_type,
			"start_time": start_time,
			"audio_url": "local_preview" # 標記為本地預覽
		}
		render_block(temp_block_data)
		
		# 清空暫存槽
		recorded_sample = null
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
