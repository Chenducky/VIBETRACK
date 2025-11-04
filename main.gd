extends Control

const TOTAL_BLOCKS: int = 16
const RECORDING_DURATION: float = 3.0  # 3 秒錄音

# @onready 變數
@onready var track_grid: GridContainer = $VBoxContainer/TrackGrid
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var record_button: Button = $"VBoxContainer/ControlsHBox/Record Button"
@onready var play_button: Button = $"VBoxContainer/ControlsHBox/Play Button"
@onready var sound_player: AudioStreamPlayer = $SoundPlayer
@onready var playback_timer: Timer = $PlaybackTimer

var track_blocks: Array[Button] = []
var sequence: Array[AudioStream] = []
var recorded_sample: AudioStreamWAV = null
var is_playing: bool = false
var current_step: int = 0

# 錄音相關變數
var is_recording: bool = false
var record_effect: AudioEffectRecord = null
var recording_timer: Timer = null
var is_audio_setup: bool = false
var record_player: AudioStreamPlayer = null  # 用於錄音的播放器

func _ready():
	print("[Main] 場景開始初始化...")
	
	# 確保所有 @onready 變數都已初始化
	if not track_grid:
		push_error("[Main] track_grid 未找到！")
		return
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
	
	# 初始化 sequence 陣列
	for i in TOTAL_BLOCKS:
		sequence.append(null)
	
	# 建立按鈕並連接訊號
	for i in TOTAL_BLOCKS:
		var button = Button.new()
		button.text = str(i + 1)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(80, 80)
		
		# 連接 pressed 訊號
		button.pressed.connect(on_track_block_pressed.bind(i))
		
		track_grid.add_child(button)
		track_blocks.append(button)
	
	print("[Main] 已建立 %d 個區塊按鈕" % TOTAL_BLOCKS)
	
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

func on_track_block_pressed(index: int):
	if recorded_sample != null:
		sequence[index] = recorded_sample
		track_blocks[index].text = "POP!"
		status_label.text = "樣本已放置到區塊 %d" % (index + 1)
	else:
		sequence[index] = null
		track_blocks[index].text = str(index + 1)
		status_label.text = "區塊 %d 已清除" % (index + 1)

func on_play_button_pressed():
	is_playing = !is_playing
	
	if is_playing:
		current_step = 0
		play_button.text = "Stop"
		playback_timer.start()
		status_label.text = "播放中..."
	else:
		play_button.text = "Play"
		playback_timer.stop()
		status_label.text = "已停止播放"

func on_playback_timer_timeout():
	if sequence[current_step] != null:
		sound_player.stream = sequence[current_step]
		sound_player.play()
	
	current_step = (current_step + 1) % TOTAL_BLOCKS
