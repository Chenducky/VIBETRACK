class_name DroppableTrack
extends Control

## DroppableTrack.gd
## 負責處理「放置」邏輯：接收拖曳過來的音檔，並呼叫 API 儲存。

@export_enum("vocal", "rhythm", "sfx") var track_type: String = "vocal"
@export var chapter: int = 1

func _ready():
	# 根據父節點名稱自動判斷類型 (如果忘記手動設定的話)
	if name.contains("Vocal"): track_type = "vocal"
	elif name.contains("Rhythm"): track_type = "rhythm"
	elif name.contains("SFX"): track_type = "sfx"

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# 只接受來自 DraggableSample 的資料
	return data is Dictionary and data.get("type") == "audio_sample"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	print("[音軌] 接收到音檔！類型: ", track_type)
	
	var start_time: float = 0.0
	
	# --- 計算放置時間 (Time Calculation) ---
	if track_type == "sfx":
		# 自由時間軸：根據 X 座標比例計算
		# 假設每個樂章 8 秒 (16拍 * 0.5秒)
		var total_duration = 8.0 
		var ratio = at_position.x / size.x
		start_time = ratio * total_duration
	else:
		# 網格系統 (Vocal/Rhythm)：根據格子計算
		# 假設這是 GridContainer，雖然它繼承 Control，但我們可以用寬度來推算
		var grid_width = size.x / 8.0 # 假設一排 8 格
		var column = int(at_position.x / grid_width)
		start_time = column * 0.5 # 每格 0.5 秒 (1拍)
	
	print("[音軌] 計算時間點: %.2f 秒" % start_time)
	
	# --- 呼叫 API 儲存 ---
	# 注意：這裡使用假 group_id，之後需改為真實 ID
	VibeTrackAPI.save_sample_to_db(
		data.sample.data, 
		track_type, 
		start_time, 
		chapter, 
		"demo_group_id"
	)
	
	# --- (視覺回饋) 產生一個暫時的方塊 ---
	var block = ColorRect.new()
	block.custom_minimum_size = Vector2(50, 50)
	block.color = Color.CYAN if track_type == "vocal" else Color.MAGENTA
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE # 讓滑鼠穿透，避免擋住後面的操作
	add_child(block)
	
	# 如果是自由時間軸，設定位置
	if track_type == "sfx":
		block.position = at_position - (block.size / 2)
