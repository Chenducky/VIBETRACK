extends Control

## VibeTrack 9.1 - 登入/註冊場景腳本

# @onready 變數 - 獲取所有 UI 節點
@onready var email_input: LineEdit = $VBoxContainer/EmailInput
@onready var password_input: LineEdit = $VBoxContainer/PasswordInput
@onready var login_button: Button = $VBoxContainer/ButtonContainer/LoginButton
@onready var register_button: Button = $VBoxContainer/ButtonContainer/RegisterButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	# 等待 SupabaseClient 初始化
	await SupabaseClient.initialized
	
	# 連接按鈕訊號
	login_button.pressed.connect(on_login_pressed)
	register_button.pressed.connect(on_register_pressed)

func on_login_pressed() -> void:
	# 從 Input 獲取 email 和 password
	var email = email_input.text.strip_edges()
	var password = password_input.text
	
	# 基本驗證
	if email.is_empty() or password.is_empty():
		status_label.text = "請輸入電子郵件和密碼"
		return
	
	# 顯示載入狀態
	status_label.text = "登入中..."
	login_button.disabled = true
	register_button.disabled = true
	
	# 呼叫 Supabase Auth API
	# 注意：Supabase 插件使用 sign_in(email, password)
	var auth_task = SupabaseClient.supabase.auth.sign_in(email, password)
	
	# 等待認證完成
	await auth_task.completed
	
	# 檢查錯誤
	if auth_task.error:
		status_label.text = auth_task.error.message if auth_task.error.message else auth_task.error.hint
	else:
		status_label.text = "登入成功！"
		# 切換到主遊戲場景
		await get_tree().create_timer(0.5).timeout  # 短暫延遲讓用戶看到成功訊息
		get_tree().change_scene_to_file("res://main.tscn")
	
	# 重新啟用按鈕
	login_button.disabled = false
	register_button.disabled = false

func on_register_pressed() -> void:
	# 從 Input 獲取 email 和 password
	var email = email_input.text.strip_edges()
	var password = password_input.text
	
	# 基本驗證
	if email.is_empty() or password.is_empty():
		status_label.text = "請輸入電子郵件和密碼"
		return
	
	# 顯示載入狀態
	status_label.text = "註冊中..."
	login_button.disabled = true
	register_button.disabled = true
	
	# 呼叫 Supabase Auth API
	# 注意：Supabase 插件使用 sign_up(email, password)
	var auth_task = SupabaseClient.supabase.auth.sign_up(email, password)
	
	# 等待認證完成
	await auth_task.completed
	
	# 檢查錯誤
	if auth_task.error:
		status_label.text = auth_task.error.message if auth_task.error.message else auth_task.error.hint
	else:
		status_label.text = "註冊成功！請檢查您的 Email 以進行驗證。"
	
	# 重新啟用按鈕
	login_button.disabled = false
	register_button.disabled = false
