class_name DroppableTrack
extends Panel

# 當音塊成功放置時發出訊號
signal sample_dropped_successfully(block_data)

@export_enum("vocal", "rhythm", "sfx") var track_type: String = "vocal"
@export var grid_columns: int = 8 

const BLOCK_PADDING: float = 10.0 
const CURRENT_USER_ID = "my_user_id" 

var grid_occupancy: Dictionary = {}

func _ready():
	if name.contains("Vocal"): track_type = "vocal"
	elif name.contains("Rhythm"): track_type = "rhythm"
	elif name.contains("SFX"): track_type = "sfx"
	
	resized.connect(queue_redraw)
	

func _draw():
	if track_type == "vocal" or track_type == "rhythm":
		var cell_width = size.x / grid_columns
		var line_color = Color(1, 1, 1, 0.2)
		for i in range(1, grid_columns):
			var x = i * cell_width
			draw_line(Vector2(x, 10), Vector2(x, size.y - 10), line_color, 2.0)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "audio_sample"

func _drop_data(at_position: Vector2, data: Variant) -> void:
	print("[音軌] 接收到音檔！類型: ", track_type)
	
	# 1. SFX 軌道處理
	if track_type == "sfx":
		_handle_sfx_drop(at_position, data)
		return

	# 2. Grid 軌道處理 (Vocal/Rhythm)
	var cell_width = size.x / grid_columns
	var target_index = int(at_position.x / cell_width)
	target_index = clampi(target_index, 0, grid_columns - 1)
	var start_time = target_index * 0.5 
	
	if grid_occupancy.has(target_index):
		var existing_block = grid_occupancy[target_index]
		if existing_block.block_data.get("user_id") == CURRENT_USER_ID:
			if data.has("origin_node") and data["origin_node"].get_parent() == self:
				var origin_block = data["origin_node"]
				var origin_index = _get_block_index(origin_block)
				_move_block_visual(existing_block, origin_index)
				grid_occupancy[origin_index] = existing_block
			else:
				return 
		else:
			return 

	if data.has("origin_node"):
		var origin_node = data["origin_node"]
		if origin_node.get_parent() == self:
			var old_index = _get_block_index(origin_node)
			if grid_occupancy.get(old_index) == origin_node:
				grid_occupancy.erase(old_index)
		origin_node.queue_free()

	_create_block_visual(data, target_index)
	
	emit_signal("sample_dropped_successfully", {
		"track_type": track_type,
		"start_time": start_time
	})

# ==========================================
#        SFX 邏輯
# ==========================================

func _handle_sfx_drop(at_position: Vector2, data: Dictionary):
	var cell_width = size.x / grid_columns
	var block_side = min(cell_width, size.y) - (BLOCK_PADDING * 2)
	var block_size = Vector2(block_side, block_side)
	
	var final_x = at_position.x - (block_side / 2)
	final_x = clamp(final_x, BLOCK_PADDING, size.x - block_side - BLOCK_PADDING)
	var center_y = (size.y - block_side) / 2
	
	# 碰撞檢查
	var proposed_rect = Rect2(Vector2(final_x, center_y), block_size)
	for child in get_children():
		if child is PlacedBlock and child != data.get("origin_node"):
			if proposed_rect.intersects(child.get_rect()):
				if child.block_data.get("user_id") == CURRENT_USER_ID:
					print("[SFX] 重疊到自己的方塊，取消！")
					return 
	
	# 移除舊實體
	if data.has("origin_node"):
		data["origin_node"].queue_free()
	
	# 建立新實體
	var block = PlacedBlock.new()
	block.size = block_size
	block.position = Vector2(final_x, center_y)
	
	if not data.has("user_id"): data["user_id"] = CURRENT_USER_ID
	data["size"] = block.size
	
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(20)
	style.bg_color = Color("#06D6A0") 
	style.shadow_size = 4
	style.shadow_color = Color(0, 0, 0, 0.2)
	
	block.setup(data, style)
	add_child(block)
	
	# [關鍵] 統一更新透明度
	call_deferred("_update_all_blocks_opacity")
	
	var start_time = (final_x / size.x) * 8.0
	emit_signal("sample_dropped_successfully", {
		"track_type": "sfx",
		"start_time": start_time
	})

func _update_all_blocks_opacity():
	# 1. 預設全體恢復不透明
	var all_blocks = []
	for child in get_children():
		if child is PlacedBlock:
			# 關鍵修復：忽略正在刪除的方塊，避免誤判
			if child.is_queued_for_deletion():
				continue
			child.modulate.a = 1.0
			all_blocks.append(child)
			
	# 2. 檢查重疊 (只針對別人的方塊)
	for victim in all_blocks:
		if victim.block_data.get("user_id") != CURRENT_USER_ID:
			var victim_rect = victim.get_rect()
			var is_covered = false
			
			for bully in all_blocks:
				if bully.block_data.get("user_id") == CURRENT_USER_ID:
					if victim_rect.intersects(bully.get_rect()):
						is_covered = true
						break 
			
			if is_covered:
				victim.modulate.a = 0.3

# ==========================================
#        Grid 輔助函式
# ==========================================

func _create_block_visual(data: Dictionary, index: int):
	var cell_width = size.x / grid_columns
	var block_side = min(cell_width, size.y) - (BLOCK_PADDING * 2)
	var block = PlacedBlock.new()
	block.size = Vector2(block_side, block_side)
	var offset_x = (cell_width - block_side) / 2
	var pos_x = (index * cell_width) + offset_x
	var pos_y = (size.y - block_side) / 2
	block.position = Vector2(pos_x, pos_y)
	if not data.has("user_id"): data["user_id"] = CURRENT_USER_ID
	data["size"] = block.size
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(20)
	if track_type == "vocal": style.bg_color = Color("#4AB0E3")
	elif track_type == "rhythm": style.bg_color = Color("#FFD166")
	block.setup(data, style)
	add_child(block)
	grid_occupancy[index] = block

func _move_block_visual(block: PlacedBlock, new_index: int):
	var cell_width = size.x / grid_columns
	var offset_x = (cell_width - block.size.x) / 2
	var pos_x = (new_index * cell_width) + offset_x
	var tween = create_tween()
	tween.tween_property(block, "position:x", pos_x, 0.2).set_trans(Tween.TRANS_CUBIC)

func _get_block_index(block: Node) -> int:
	var cell_width = size.x / grid_columns
	return int((block.position.x + block.size.x/2) / cell_width)
