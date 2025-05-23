extends Control

@export var timer:Timer
@export var time_label:Label
@export var start_pause_button:Button
@export var reset_button:Button

var work_duration := 25 * 60  # 25 минут
var break_duration := 5 * 60  # 5 минут
var time_left := work_duration
var is_running := false
var is_work_period := true
var volume:= 70:
	set(value):
		volume = value
		$AudioStreamPlayer.volume_db = linear_to_db(value / 100.0)
		$SettingsPanel/MarginContainer/VBoxContainer/HBoxContainer3/HSlider.value = value
var top:=false:
	set(value):
		top = value
		$SettingsPanel/MarginContainer/VBoxContainer/HBoxContainer5/TopCheckBox.button_pressed = value
		get_viewport().set_flag(Window.FLAG_ALWAYS_ON_TOP, value)
		
		

const SAVE_PATH := "user://settings.json"

var count_working_period := 0:
	set(value):
		count_working_period = value
		$MainPanel/MarginContainer/VBoxContainer/HBoxContainer2/CountLabel.text = str(value)

func _ready():
	load_settings()
	$SettingsPanel/MarginContainer/VBoxContainer/HBoxContainer/WorkTimeEdit.value = work_duration/60
	$SettingsPanel/MarginContainer/VBoxContainer/HBoxContainer2/RestWorkEdit.value = break_duration/60
	time_left = work_duration
	update_time_label()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_timer_timeout)
	start_pause_button.text = "Start"
	reset_button.pressed.connect(_on_reset_pressed)
	start_pause_button.pressed.connect(_on_start_pause_pressed)
	if OS.get_name() == 'Web':
		request_web_notification_permission()

var start_time

func _on_start_pause_pressed():
	start_time = Time.get_unix_time_from_system()
	if is_running:
		timer.stop()
		is_running = false
		start_pause_button.text = "Start"
	else:
		timer.start()
		is_running = true
		start_pause_button.text = "Pause"

func _on_reset_pressed():
	timer.stop()
	is_running = false
	is_work_period = true
	time_left = work_duration
	update_time_label()
	start_pause_button.text = "Start"

func _on_timer_timeout():
	time_left -= 1
	update_time_label()

	if time_left <= 0:
		timer.stop()
		is_running = false
		_on_period_complete()

func _on_period_complete():
	if is_work_period:
		time_left = break_duration
		is_work_period = false
		start_pause_button.text = "Start Break"
		count_working_period += 1
		save_settings()
		log_work_period(work_duration/60)
		send_notify("Pomodoro complitied!", "Make break")
	else:
		time_left = work_duration
		is_work_period = true
		start_pause_button.text = "Start Work"
		send_notify("Break finised!", "Start work")
	update_time_label()
	$AudioStreamPlayer.play()


func update_time_label():
	var minutes = time_left / 60
	var seconds = int(time_left) % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]


func _on_settings_button_pressed() -> void:
	$MainPanel.hide()
	$SettingsPanel.show()


func _on_back_button_pressed() -> void:
	$SettingsPanel.hide()
	$MainPanel.show()
	$TreePanel.hide()


func _on_work_time_edit_value_changed(value: float) -> void:
	work_duration = float(value) * 60
	if !is_running && is_work_period:
		time_left  = work_duration
		update_time_label()
	save_settings()


func _on_rest_work_edit_value_changed(value: float) -> void:
	break_duration = float(value) * 60
	if !is_running && !is_work_period:
		time_left  = break_duration
		update_time_label()
	save_settings()


func _on_h_slider_value_changed(value: float) -> void:
	volume = value
	save_settings()


func save_settings() -> void:
	var data := {
		"work_duration": work_duration,
		"break_duration": break_duration,
		"count_working_period": count_working_period,
		"volume": volume,
		"top": top,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))  # "\t" — для форматирования
		file.close()


func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var text := file.get_as_text()
		var result = JSON.parse_string(text)
		if result is Dictionary and result.has("volume"):
			volume = result["volume"]
			count_working_period = result["count_working_period"]
			work_duration = result["work_duration"]
			break_duration = result["break_duration"]
			top = result["top"]


func _on_top_check_box_toggled(toggled_on: bool) -> void:
	top = toggled_on
	save_settings()


func send_notify(title:String="", message:String="") -> void:
	var path = copy_icon_to_userdir("res://assets/PomodoroTimer.png", "PomodoroTimer.png")
	if OS.get_name() == 'Linux':
		OS.execute('notify-send', ['-a', ProjectSettings.get_setting("application/config/name"), "-i", path, title, message])
	elif OS.get_name() == 'Web':
		request_web_notification_permission()
		send_web_notification(title, message)


func send_web_notification(title: String, body: String):
	JavaScriptBridge.eval('''
		if (Notification.permission === "granted") {
			new Notification("%s", { body: "%s" });
		}
	''' % [title, body])

func request_web_notification_permission():
	JavaScriptBridge.eval("""
		if (Notification.permission !== "granted") {
			Notification.requestPermission();
		}
	""")


func copy_icon_to_userdir(res_path: String, file_name: String) -> String:
	var icon_data = FileAccess.open(res_path, FileAccess.READ)
	if icon_data == null:
		push_error("Не удалось открыть " + res_path)
		return ""

	var dest_path = "user://%s" % file_name
	var out_file = FileAccess.open(dest_path, FileAccess.WRITE)
	if out_file == null:
		push_error("Не удалось создать " + dest_path)
		return ""

	out_file.store_buffer(icon_data.get_buffer(icon_data.get_length()))
	out_file.close()
	icon_data.close()

	return ProjectSettings.globalize_path(dest_path)  # абсолютный путь для notify-send


const CSV_PATH := "user://work_log.csv"

func log_work_period(duration_minutes: int) -> void:
	var file_exists = FileAccess.file_exists(CSV_PATH)
	var file
	if not file_exists:
		file = FileAccess.open(CSV_PATH, FileAccess.WRITE)
		file.store_csv_line(["date","time","duration_minutes"])  # заголовок
		file.close()
	var now = Time.get_datetime_dict_from_system()
	var date = "%04d-%02d-%02d" % [now.year, now.month, now.day]
	var time = "%02d:%02d" % [now.hour, now.minute]
	
	file = FileAccess.open(CSV_PATH, FileAccess.READ)
	var text :Array = []
	while not file.eof_reached():
		var line = file.get_line()
		if line:
			text.append(line)
	file.close()
	print(text)
	file = FileAccess.open(CSV_PATH, FileAccess.WRITE)
	for l in text:
		file.store_line(l)
	file.store_csv_line([date, time, duration_minutes])
	file.close()

@export var work_log_tree: Tree

func load_work_log() -> void:
	var file = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file:
		var root = work_log_tree.create_item()
		work_log_tree.clear()
		work_log_tree.set_columns(3)
		work_log_tree.set_column_titles_visible(true)
		work_log_tree.set_column_title(0, "Дата")
		work_log_tree.set_column_title(1, "Время")
		work_log_tree.set_column_title(2, "Минут")
		var title := true
		while not file.eof_reached():
			var parts = file.get_csv_line()
			if title:
				title = false
				continue  # пропустить заголовок
			if parts.size() == 3:
				var item = work_log_tree.create_item()
				item.set_text(0, parts[0])
				item.set_text(1, parts[1])
				item.set_text(2, parts[2])
		file.close()


func _on_log_button_pressed() -> void:
	load_work_log()
	$MainPanel.hide()
	$TreePanel.show()
