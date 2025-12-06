class_name DraggableSample
extends Panel

## DraggableSample.gd
## 負責處理「拖曳」邏輯：產生半透明的預覽圖。

# 這裡儲存錄好的音檔
var audio_sample: AudioStreamWAV = null

func set_sample(sample: AudioStreamWAV):
	audio_sample = sample
	self.modulate = Color.WHITE 
	$Label.text = "🎵 拖曳我" # 可以改成音符圖案

func clear_sample():
	audio_sample = null
	self.modulate = Color(1, 1, 1, 0.5)
	$Label.text = "空"

func _get_drag_data(_at_position: Vector2) -> Variant:
	if audio_sample == null:
		return null
		
	# 1. 準備資料包
	var data = {
		"type": "audio_sample",
		"sample": audio_sample
	}
	
	# 2. 建立拖曳預覽 (Ghost Icon)
	# 我們做一個跟自己長得很像的 Panel，但是半透明
	var preview = Panel.new()
	preview.size = Vector2(100, 100) # 設定一個固定大小，不要太大
	preview.modulate = Color(1, 1, 1, 0.5) # 半透明 (0.5)
	
	# 加個圖示或文字在中間
	var icon = Label.new()
	icon.text = "🎵"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(icon)
	
	# 加上旋轉效果，感覺更有動感 (選用)
	preview.rotation_degrees = 5 
	
	# 設定中心點為滑鼠位置 (這樣才不會拿著左上角)
	# 注意：set_drag_preview 的 Control 預設中心在左上，我們要偏移
	var c = Control.new()
	c.add_child(preview)
	preview.position = -preview.size / 2 # 往左上偏移一半寬高
	
	set_drag_preview(c)
	
	return data
