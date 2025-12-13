@tool
class_name DroppableTrackV2
extends Panel

signal sample_dropped_successfully(block_data)
@export_enum("vocal", "rhythm", "sfx") var track_type: String = "vocal"

# 輸入數字越大 = 格子越小
@export var visible_grids: int = 12 :
	set(value):
		visible_grids = max(1, value)
		if is_inside_tree(): _recalculate_layout()

# --- 動態章節設定 ---
var chapter_width: float = 0.0          
var grids_per_chapter: int = 13
var tail_buffer_seconds: float = 1.0

# 狀態變數
var total_chapters: int = 4         
var current_active_chapter: int = 1 
var unlocked_chapters: int = 1      

const BLOCK_PADDING: float = 6.0  
const CURRENT_USER_ID = "my_user_id" 

func _ready():
	if name.contains("Vocal"): track_type = "vocal"
	elif name.contains("Rhythm"): track_type = "rhythm"
	elif name.contains("SFX"): track_type = "sfx"
	
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER 
	
	if not Engine.is_editor_hint():
		get_tree().root.size_changed.connect(func(): _recalculate_layout())
	
	call_deferred("_recalculate_layout")

func _recalculate_layout():
	var available_width = 1080.0
	if is_inside_tree():
		if get_parent() and get_parent() is Control and get_parent().size.x > 0:
			available_width = get_parent().size.x
		elif get_viewport_rect().size.x > 0:
			available_width = get_viewport_rect().size.x

	# 1. 計算格子大小 (高度)
	var cell_size = available_width / float(visible_grids)
	cell_size = min(cell_size, 250.0) 
	
	# 2. [核心修正] 強制章節寬度 = 格數 x 格子大小
	# 這樣保證每一個格子都是完美的正方形，不會有長方形出現
	chapter_width = float(grids_per_chapter) * cell_size
	
	# 3. 設定尺寸
	var new_min_size = Vector2(total_chapters * chapter_width, cell_size)
	
	if custom_minimum_size != new_min_size:
		custom_minimum_size = new_min_size
		size = new_min_size
		queue_redraw()

func _draw():
	if chapter_width <= 0: return

	# 計算單格寬度 (因為我們強制了總寬，所以除以格數一定等於高度)
	var cell_width = chapter_width / float(grids_per_chapter)
	
	for c in range(1, total_chapters + 1):
		var chapter_start_x = (c - 1) * chapter_width
		
		# 畫格子
		if track_type == "vocal" or track_type == "rhythm":
			var line_color = Color(1, 1, 1, 0.2) 
			for i in range(1, grids_per_chapter): 
				var x = chapter_start_x + (i * cell_width)
				draw_line(Vector2(x, 0), Vector2(x, size.y), line_color, 2.0)
		
		# 章節分隔線
		draw_line(Vector2(c * chapter_width, 0), Vector2(c * chapter_width, size.y), Color(0, 0, 0, 0.3), 2.0)

		# 遮罩
		if c > unlocked_chapters:
			var rect = Rect2(chapter_start_x - 1, 0, chapter_width + 1, size.y)
			draw_rect(rect, Color(0, 0, 0, 0.5)) 

# --- 接收來自 Main 的設定 ---
func update_chapter_config(grids: int, tail: float, current: int, unlocked: int, total: int):
	grids_per_chapter = grids
	tail_buffer_seconds = tail
	current_active_chapter = current
	unlocked_chapters = unlocked
	total_chapters = total
	call_deferred("_recalculate_layout")

# --- 拖曳邏輯 ---
func _is_position_valid(local_x: float) -> bool:
	var target_chapter = int(local_x / chapter_width) + 1
	if target_chapter != current_active_chapter: return false
	
	var x_in_chapter = fmod(local_x, chapter_width)
	# 這裡也要用新的 cell_width 算法
	var cell_width = chapter_width / float(grids_per_chapter)
	
	if x_in_chapter > (grids_per_chapter * cell_width) + 0.1: return false
	return true

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == "audio_sample"): return false
	return _is_position_valid(at_position.x)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _is_position_valid(at_position.x): return
	
	var cell_width = chapter_width / float(grids_per_chapter)
	
	if track_type == "sfx":
		_handle_sfx_drop(at_position, data, cell_width)
		return

	var x_in_chapter = fmod(at_position.x, chapter_width)
	var grid_index_in_chapter = int(x_in_chapter / cell_width)
	var current_chap_offset = (current_active_chapter - 1) * grids_per_chapter
	var global_target_index = current_chap_offset + grid_index_in_chapter
	
	if data.has("origin_node"): data["origin_node"].queue_free()
	_create_block_visual(data, global_target_index, cell_width)
	
	# [注意] 這裡每格固定 3 秒
	var start_time = ((current_active_chapter - 1) * grids_per_chapter * 3.0) + (grid_index_in_chapter * 3.0)
	emit_signal("sample_dropped_successfully", {"track_type": track_type, "start_time": start_time})

func _create_block_visual(data: Dictionary, global_index: int, cell_width: float):
	var block_side = min(cell_width, size.y) - (BLOCK_PADDING * 2)
	var block = PlacedBlock.new()
	block.size = Vector2(block_side, block_side)
	
	var chap_idx = int(global_index / grids_per_chapter)
	var grid_idx = global_index % grids_per_chapter
	var chap_start_x = chap_idx * chapter_width
	
	var pos_x = chap_start_x + (grid_idx * cell_width) + (cell_width - block_side)/2
	var pos_y = (size.y - block_side) / 2
	block.position = Vector2(pos_x, pos_y)
	
	if not data.has("user_id"): data["user_id"] = CURRENT_USER_ID
	data["size"] = block.size
	
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(16)
	if track_type == "vocal": style.bg_color = Color("#4AB0E3")
	elif track_type == "rhythm": style.bg_color = Color("#FFD166")
	block.setup(data, style)
	add_child(block)

func _handle_sfx_drop(at_position: Vector2, data: Dictionary, cell_width: float):
	var block_side = min(cell_width, size.y) - (BLOCK_PADDING * 2)
	var final_x = clamp(at_position.x - block_side/2, BLOCK_PADDING, (unlocked_chapters * chapter_width) - block_side)
	if not _is_position_valid(final_x + block_side/2): return
	if data.has("origin_node"): data["origin_node"].queue_free()
	
	var block = PlacedBlock.new()
	block.size = Vector2(block_side, block_side)
	block.position = Vector2(final_x, (size.y - block_side)/2)
	
	if not data.has("user_id"): data["user_id"] = CURRENT_USER_ID
	data["size"] = block.size
	
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(16)
	style.bg_color = Color("#06D6A0") 
	block.setup(data, style)
	add_child(block)
	
	var start_time = (final_x / chapter_width) * float(grids_per_chapter) * 3.0
	emit_signal("sample_dropped_successfully", {"track_type": "sfx", "start_time": start_time})
