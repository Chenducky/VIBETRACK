class_name PlacedBlock
extends Panel

## PlacedBlock.gd
## 升級版：支援「事件穿透」，讓新方塊可以疊在舊方塊上。

var block_data: Dictionary = {}

func setup(data: Dictionary, style_box: StyleBoxFlat):
	block_data = data
	add_theme_stylebox_override("panel", style_box)
	
	# 設定滑鼠過濾器：PASS (關鍵！讓它可以被點擊拖曳，也能把事件傳給底下)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	if data.has("size"): size = data.size
	
	var label = Label.new()
	# 如果是別人的，顯示鎖頭或名字
	if data.get("user_id") != "my_user_id":
		label.text = "" # 保持乾淨，或是放 icon
	else:
		label.text = "" 
	
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(label)

# --- 拖曳邏輯 (我被抓起來) ---
func _get_drag_data(_at_position: Vector2) -> Variant:
	if block_data.get("user_id") != "my_user_id":
		return null # 別人的不能動
	
	var drag_data = block_data.duplicate()
	drag_data["type"] = "audio_sample"
	drag_data["origin_node"] = self 
	
	var preview = Panel.new()
	preview.size = size
	preview.add_theme_stylebox_override("panel", get_theme_stylebox("panel").duplicate())
	preview.modulate = Color(1, 1, 1, 0.5)
	preview.rotation_degrees = 5
	
	var c = Control.new()
	c.add_child(preview)
	preview.position = -preview.size / 2
	set_drag_preview(c)
	
	return drag_data

# --- [關鍵修復] 放置轉發邏輯 (別人丟東西給我) ---

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# 詢問父節點 (DroppableTrack) 是否接受這個位置
	var parent = get_parent()
	if parent and parent.has_method("_can_drop_data"):
		# 注意：要加上自己的 position，因為 at_position 是相對於我的
		return parent._can_drop_data(position + at_position, data)
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	# 將放置事件轉發給父節點
	var parent = get_parent()
	if parent and parent.has_method("_drop_data"):
		parent._drop_data(position + at_position, data)
