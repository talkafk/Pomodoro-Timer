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
	update_time_label()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_timer_timeout)
	start_pause_button.text = "Start"
	reset_button.pressed.connect(_on_reset_pressed)
	start_pause_button.pressed.connect(_on_start_pause_pressed)

func _on_start_pause_pressed():
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
	else:
		time_left = work_duration
		is_work_period = true
		start_pause_button.text = "Start Work"
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


func _on_work_time_edit_value_changed(value: float) -> void:
	work_duration = float(value) * 60
	save_settings()


func _on_rest_work_edit_value_changed(value: float) -> void:
	break_duration = float(value) * 60
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
