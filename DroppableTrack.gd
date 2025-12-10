class_name DroppableTrack
extends Panel

# 當音塊成功放置時發出訊號
signal sample_dropped_successfully(block_data)

@export_enum("vocal", "rhythm", "sfx") var track_type: String = "vocal"

# --- 章節系統設定 ---
@export var grid_columns_per_chapter: int = 8 # 每一章有 8 格
@export var chapter_width: float = 1080.0 # 每一章的寬度 (預設手機寬度)
var current_active_chapter: int = 1 # 目前正在遊玩(可編輯)的章節
var unlocked_chapters: int = 1      # 總共解鎖到第幾章

const BLOCK_PADDING: float = 10.0 
const CURRENT_USER_ID = "my_user_id" 

var grid_occupancy: Dictionary = {}

func _ready():
	if name.contains("Vocal"): track_type = "vocal"
	elif name.contains("Rhythm"): track_type = "rhythm"
	elif name.contains("SFX"): track_type = "sfx"
	
	resized.connect(queue_redraw)
	
	# [測試用] 預設開啟 2 個章節，讓你測試左右滑動與鎖定功能
	# 正式版請在 main.gd 控制這些變數
	unlocked_chapters = 2
	current_active_chapter = 2 
	# 強制設定寬度為 2 章
	custom_minimum_size.x = unlocked_chapters * chapter_width
	size.x = custom_minimum_size.x

func _draw():
	# 1. 畫出章節的分隔線與遮罩
	for c in range(1, unlocked_chapters + 1):
		var x = c * chapter_width
		# 畫章節分隔線 (粗黑線)
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color.BLACK, 5.0)
		
		# 畫出「鎖定」遮罩 (針對非當前章節)
		if c != current_active_chapter:
			var rect = Rect2((c-1) * chapter_width, 0, chapter_width, size.y)
			draw_rect(rect, Color(0, 0, 0, 0.3)) # 30% 黑色半透明

	# 2. 畫格子 (只畫在解鎖區域)
	if track_type == "vocal" or track_type == "rhythm":
		var total_grid_count = grid_columns_per_chapter * unlocked_chapters
		var cell_width = chapter_width / grid_columns_per_chapter
		var line_color = Color(1, 1, 1, 0.2)
		
		for i in range(1, total_grid_count):
			var x = i * cell_width
			# 略過剛好是章節分隔線的地方
			if int(x) % int(chapter_width) != 0:
				draw_line(Vector2(x, 10), Vector2(x, size.y - 10), line_color, 2.0)

# --- [核心] 檢查位置是否可編輯 ---
func _is_position_editable(local_x: float) -> bool:
	# 計算這個 x 座標屬於第幾章
	var target_chapter = int(local_x / chapter_width) + 1
	
	if target_chapter != current_active_chapter:
		# print("[權限] 目標在第 %d 章 (唯讀)，當前只能編輯第 %d 章" % [target_chapter, current_active_chapter])
		return false
	return true

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == "audio_sample"):
		return false
	
	# 拖曳時就檢查是否在可編輯區域
	if not _is_position_editable(at_position.x):
		return false
		
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 再次檢查 (雙重保險)
	if not _is_position_editable(at_position.x):
		return

	print("[音軌] 接收到音檔！類型: ", track_type)
	
	# --- 1. SFX 軌道處理 ---
	if track_type == "sfx":
		_handle_sfx_drop(at_position, data)
		return

	# --- 2. Grid 軌道處理 ---
	var cell_width = chapter_width / grid_columns_per_chapter
	var target_index = int(at_position.x / cell_width)
	
	# 限制範圍
	var max_index = (grid_columns_per_chapter * unlocked_chapters) - 1
	target_index = clampi(target_index, 0, max_index)
	
	var start_time = target_index * 0.5 
	
	if grid_occupancy.has(target_index):
		var existing_block = grid_occupancy[target_index]
		if existing_block.block_data.get("user_id") == CURRENT_USER_ID:
			if data.has("origin_node") and data["origin_node"].get_parent() == self:
				# 移動來源也要檢查是否鎖定 (防止把舊章節的東西移出來)
				if not _is_position_editable(data["origin_node"].position.x):
					return
					
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
		# 移動來源檢查
		if not _is_position_editable(origin_node.position.x):
			return
			
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
#        SFX 邏輯 (含章節邊界檢查)
# ==========================================

func _handle_sfx_drop(at_position: Vector2, data: Dictionary):
	var cell_width = chapter_width / grid_columns_per_chapter
	var block_side = min(cell_width, size.y) - (BLOCK_PADDING * 2)
	var block_size = Vector2(block_side, block_side)
	
	var final_x = at_position.x - (block_side / 2)
	
	# 邊界限制：只能在已解鎖的範圍內
	final_x = clamp(final_x, BLOCK_PADDING, (unlocked_chapters * chapter_width) - block_side - BLOCK_PADDING)
	
	# [關鍵] 再次檢查最終位置是否在當前章節 (因為 clamp 可能把它拉回舊章節邊緣)
	if not _is_position_editable(final_x + block_side/2):
		return
		
	var center_y = (size.y - block_side) / 2
	
	# 碰撞檢查
	var proposed_rect = Rect2(Vector2(final_x, center_y), block_size)
	for child in get_children():
		if child is PlacedBlock and child != data.get("origin_node"):
			if proposed_rect.intersects(child.get_rect()):
				if child.block_data.get("user_id") == CURRENT_USER_ID:
					return 
	
	if data.has("origin_node"):
		# 檢查來源是否鎖定
		if not _is_position_editable(data["origin_node"].position.x):
			return
		data["origin_node"].queue_free()
	
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
	
	call_deferred("_update_all_blocks_opacity")
	
	var start_time = (final_x / chapter_width) * 8.0 # 假設每章 8 秒
	emit_signal("sample_dropped_successfully", {
		"track_type": "sfx",
		"start_time": start_time
	})

# ==========================================
#        輔助與更新函式
# ==========================================

func _update_all_blocks_opacity():
	var all_blocks = []
	for child in get_children():
		if child is PlacedBlock:
			if child.is_queued_for_deletion(): continue
			child.modulate.a = 1.0
			all_blocks.append(child)
			
	for victim in all_blocks:
		if victim.block_data.get("user_id") != CURRENT_USER_ID:
			var victim_rect = victim.get_rect()
			var is_covered = false
			for bully in all_blocks:
				if bully.block_data.get("user_id") == CURRENT_USER_ID:
					if victim_rect.intersects(bully.get_rect()):
						is_covered = true
						break 
			if is_covered: victim.modulate.a = 0.3

func _create_block_visual(data: Dictionary, index: int):
	var cell_width = chapter_width / grid_columns_per_chapter
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
	var cell_width = chapter_width / grid_columns_per_chapter
	var offset_x = (cell_width - block.size.x) / 2
	var pos_x = (new_index * cell_width) + offset_x
	var tween = create_tween()
	tween.tween_property(block, "position:x", pos_x, 0.2).set_trans(Tween.TRANS_CUBIC)

func _get_block_index(block: Node) -> int:
	var cell_width = chapter_width / grid_columns_per_chapter
	return int((block.position.x + block.size.x/2) / cell_width)

# 外部呼叫：更新章節資訊
func update_chapter_info(chapter: int, unlocked: int):
	current_active_chapter = chapter
	unlocked_chapters = unlocked
	custom_minimum_size.x = unlocked_chapters * chapter_width
	size.x = custom_minimum_size.x 
	queue_redraw()
