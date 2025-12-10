@tool  # <--- 這行一定要在最上面！
class_name DroppableTrackV2
extends Panel

signal sample_dropped_successfully(block_data)
@export_enum("vocal", "rhythm", "sfx") var track_type: String = "vocal"

# --- [新功能] 視覺縮放滑桿 ---
# 這裡設定範圍 4 到 24，預設值 12
# [無限制版] 您可以輸入任何數字 (例如 50)，數字越大格子越小
@export var visible_grids: int = 12 :
	set(value):
		# [防呆] 強制最小為 1，防止輸入 0 導致除以零當機
		visible_grids = max(1, value)
		
		# 數值改變時，立即重算佈局
		if is_inside_tree():
			_recalculate_layout()

# --- 動態章節設定 ---
var chapter_width: float = 0.0          
var seconds_per_chapter: int = 40
var grids_per_chapter: int = 13
var tail_buffer_seconds: int = 1

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
	
	# 連接訊號 (防止編輯器報錯)
	if not Engine.is_editor_hint():
		get_tree().root.size_changed.connect(func(): _recalculate_layout())
	
	# 初始計算
	_recalculate_layout()

# [防震版] 重新計算佈局
func _recalculate_layout():
	# 1. 抓取寬度
	var available_width = 1080.0
	if is_inside_tree():
		available_width = get_viewport_rect().size.x
		if get_parent() and get_parent() is Control and get_parent().size.x > 0:
			available_width = get_parent().size.x

	# 2. 計算一格寬度
	var cell_size = available_width / float(visible_grids)
	cell_size = min(cell_size, 200.0) # 限制最大高度
	
	# 3. 計算總寬度
	var px_per_sec = cell_size / 3.0
	chapter_width = px_per_sec * seconds_per_chapter
	
	# 4. 設定尺寸
	var new_min_size = Vector2(total_chapters * chapter_width, cell_size)
	
	if custom_minimum_size != new_min_size:
		custom_minimum_size = new_min_size
		size = new_min_size
		queue_redraw()

func _draw():
	if chapter_width <= 0: return

	var px_per_sec = chapter_width / float(seconds_per_chapter) if seconds_per_chapter > 0 else 0.0
	var cell_width = px_per_sec * 3.0 
	
	for c in range(1, total_chapters + 1):
		var chapter_start_x = (c - 1) * chapter_width
		
		if track_type == "vocal" or track_type == "rhythm":
			var line_color = Color(1, 1, 1, 0.2) 
			for i in range(1, grids_per_chapter): 
				var x = chapter_start_x + (i * cell_width)
				draw_line(Vector2(x, 0), Vector2(x, size.y), line_color, 2.0)
		
		draw_line(Vector2(c * chapter_width, 0), Vector2(c * chapter_width, size.y), Color(0, 0, 0, 0.3), 2.0)

		if c > unlocked_chapters:
			var rect = Rect2(chapter_start_x - 1, 0, chapter_width + 1, size.y)
			draw_rect(rect, Color(0, 0, 0, 0.5)) 

func update_chapter_config(grids: int, tail: int, sec_per_chap: int, current: int, unlocked: int, total: int):
	grids_per_chapter = grids
	tail_buffer_seconds = tail
	seconds_per_chapter = sec_per_chap
	current_active_chapter = current
	unlocked_chapters = unlocked
	total_chapters = total
	_recalculate_layout()

# --- 拖曳邏輯區 (與之前相同，略過不變) ---
func _is_position_valid(local_x: float) -> bool:
	var target_chapter = int(local_x / chapter_width) + 1
	if target_chapter != current_active_chapter: return false
	var x_in_chapter = fmod(local_x, chapter_width)
	var px_per_sec = chapter_width / float(seconds_per_chapter) if seconds_per_chapter > 0 else 0.0
	var cell_width = px_per_sec * 3.0
	if x_in_chapter > (grids_per_chapter * cell_width) + 0.1: return false
	return true

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == "audio_sample"): return false
	return _is_position_valid(at_position.x)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _is_position_valid(at_position.x): return
	var px_per_sec = chapter_width / float(seconds_per_chapter) if seconds_per_chapter > 0 else 0.0
	var cell_width = px_per_sec * 3.0
	if track_type == "sfx":
		_handle_sfx_drop(at_position, data, cell_width)
		return
	var x_in_chapter = fmod(at_position.x, chapter_width)
	var grid_index_in_chapter = int(x_in_chapter / cell_width)
	var current_chap_offset = (current_active_chapter - 1) * grids_per_chapter
	var global_target_index = current_chap_offset + grid_index_in_chapter
	if data.has("origin_node"): data["origin_node"].queue_free()
	_create_block_visual(data, global_target_index, cell_width)
	var start_time = ((current_active_chapter - 1) * seconds_per_chapter) + (grid_index_in_chapter * 3.0)
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
	var start_time = (final_x / chapter_width) * float(seconds_per_chapter)
	emit_signal("sample_dropped_successfully", {"track_type": "sfx", "start_time": start_time})
