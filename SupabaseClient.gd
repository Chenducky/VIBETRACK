extends Node

## VibeTrack 9.1 - Supabase 客戶端 Autoload
## 全域 Supabase 客戶端包裝器

var supabase: Node

# 配置資訊（從 Supabase 網站獲取）
const SUPABASE_URL: String = "https://xypsjytjvzgubvbzjzag.supabase.co"
const SUPABASE_KEY: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh5cHNqeXRqdnpndWJ2YnpqemFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIwMjM5NjQsImV4cCI6MjA3NzU5OTk2NH0.dWzJUv3bEjAb5SUMi_ARpQTd5HDDl95vDCmU80F6e4A"

# 初始化狀態
var is_initialized: bool = false

# 訊號
signal initialized

func _init() -> void:
	# 在 _init() 中立即設定配置，這會在 Supabase 的 _ready() 之前執行
	# 由於 Autoload 按順序初始化，我們需要在下一幀嘗試設定
	# 但更好的方法是在 Supabase 的 _ready() 執行時，config 已經有值
	pass

func _ready() -> void:
	# 等待一幀，確保所有 Autoload 都已建立節點
	await get_tree().process_frame
	
	# 檢查 Supabase Autoload 是否存在
	if not has_node("/root/Supabase"):
		push_error("Supabase Autoload 未找到！請確認 project.godot 中已配置 Supabase Autoload")
		return
	
	supabase = get_node("/root/Supabase")
	
	# 設定配置（在 Supabase 的 _ready() 之後，但可以重新初始化）
	if SUPABASE_URL != "YOUR_SUPABASE_URL" and SUPABASE_KEY != "YOUR_SUPABASE_ANON_KEY":
		# 設定配置（即使 Supabase 已經初始化）
		supabase.config["supabaseUrl"] = SUPABASE_URL
		supabase.config["supabaseKey"] = SUPABASE_KEY
		
		# 重新設定 header（包含 API key）
		supabase.header = PackedStringArray([
			"Content-Type: application/json",
			"Accept: application/json",
			"apikey: %s" % SUPABASE_KEY
		])
		
		# 重新建立服務節點（使用正確的配置）
		if supabase.auth:
			supabase.remove_child(supabase.auth)
			supabase.auth.queue_free()
		if supabase.database:
			supabase.remove_child(supabase.database)
			supabase.database.queue_free()
		if supabase.realtime:
			supabase.remove_child(supabase.realtime)
			supabase.realtime.queue_free()
		if supabase.storage:
			supabase.remove_child(supabase.storage)
			supabase.storage.queue_free()
		
		# 重新載入服務節點（使用新的配置）
		supabase.load_nodes()
	
	is_initialized = true
	initialized.emit()
	
	print("[SupabaseClient] 初始化完成，配置已設定")

# ============================================
# 便捷訪問方法
# ============================================

## 獲取 Auth 服務
func auth() -> SupabaseAuth:
	if not is_initialized:
		push_error("SupabaseClient 尚未初始化")
		return null
	return supabase.auth

## 獲取 Database 服務
func database() -> SupabaseDatabase:
	if not is_initialized:
		push_error("SupabaseClient 尚未初始化")
		return null
	return supabase.database

## 獲取 Storage 服務
func storage() -> SupabaseStorage:
	if not is_initialized:
		push_error("SupabaseClient 尚未初始化")
		return null
	return supabase.storage

## 獲取 Realtime 服務
func realtime() -> SupabaseRealtime:
	if not is_initialized:
		push_error("SupabaseClient 尚未初始化")
		return null
	return supabase.realtime

# ============================================
# 檢查配置
# ============================================

func check_config() -> void:
	if SUPABASE_URL == "YOUR_SUPABASE_URL" or SUPABASE_KEY == "YOUR_SUPABASE_ANON_KEY":
		push_warning("請記得在 SupabaseClient.gd 中替換 SUPABASE_URL 和 SUPABASE_KEY！")
