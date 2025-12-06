class_name DraggableSample
extends Panel

## DraggableSample.gd
## 掛載在「StagingSlot」上，讓錄好的聲音可以被拖曳。

# 這裡儲存錄好的音檔
var audio_sample: AudioStreamWAV = null

func set_sample(sample: AudioStreamWAV):
	audio_sample = sample
	# 視覺提示：變色代表有東西
	self.modulate = Color.WHITE 
	$Label.text = "拖曳我！"

func clear_sample():
	audio_sample = null
	self.modulate = Color(1, 1, 1, 0.5) # 變半透明
	$Label.text = "空"

func _get_drag_data(_at_position: Vector2) -> Variant:
	if audio_sample == null:
		return null
		
	print("[樣本] 開始拖曳...")
	
	# 1. 準備資料包
	var data = {
		"type": "audio_sample",
		"sample": audio_sample
	}
	
	# 2. 建立拖曳時的預覽圖 (跟著滑鼠跑的小圖示)
	var preview = Label.new()
	preview.text = "🎵"
	preview.modulate = Color.YELLOW
	set_drag_preview(preview)
	
	return data
