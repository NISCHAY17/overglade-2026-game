extends CharacterBody2D

# =====================
# LOGGING
# =====================
func npc_log(msg: String) -> void:
	var mode_string = "UNKNOWN"
	if talk_mode >= 0 and talk_mode < TalkMode.keys().size():
		mode_string = TalkMode.keys()[talk_mode]
	print("[NPC:%s][MODE:%s] %s" % [npc_name, mode_string, msg])

# =====================
# REFERENCES
# =====================
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var http: HTTPRequest = $HTTPRequest
@onready var talk_area: Area2D = $TalkArea

@onready var instruct_label: Node = $Instruct 

@onready var char1_node: Node2D = $CHAR1
@onready var input_node: Node2D = $CHAR1/INPUT
@onready var output_node: Node2D = $CHAR1/OUTPUT

@onready var input_box: LineEdit = $CHAR1/INPUT/LineEdit
@onready var output_box: RichTextLabel = $CHAR1/OUTPUT/RichTextLabel
@onready var name_label: Label = $"CHAR1/OUTPUT/NAME LABEL"
@onready var portrait: Sprite2D = $"CHAR1/OUTPUT/Vilchar3png"

# =====================
# CONFIG
# =====================
@export var npc_name: String = "Villager"
@export var npc_age: int = 45
@export var npc_family: String = "wife and two kids"
@export var npc_fear: String = "radiation making his daughter sick"
@export var npc_dream: String = "send his son to college"
@export var npc_think_time: float = 2.0 

var api_key: String = "AIzaSyBbFZigEmH_VQnU-bvMGcZ4mUl3ZSkqVPw"

# =====================
# PROGRESSION
# =====================
var trust_level: int = 0
var mentioned_money: bool = false
var mentioned_safety: bool = false
var mentioned_community: bool = false

# =====================
# STATES
# =====================
enum TalkMode { NONE, NPC_SPEAKING, PLAYER_TYPING, WAITING_AI }
var talk_mode: TalkMode = TalkMode.NONE

var player_near: bool = false
var talking: bool = false
var convinced: bool = false

var messages: Array[Dictionary] = []

# =====================
# READY
# =====================
func _ready() -> void:
	sprite.play("IDLE")
	_set_talk_mode(TalkMode.NONE)
	
	if instruct_label:
		instruct_label.visible = false

	input_box.text_submitted.connect(_on_player_input)
	talk_area.body_entered.connect(_on_body_entered)
	talk_area.body_exited.connect(_on_body_exited)

	npc_log("Initialized and ready.")

# =====================
# PROCESS
# =====================
func _process(_delta: float) -> void:
	if instruct_label:
		instruct_label.visible = player_near and not talking and not convinced

	if player_near and not talking and not convinced:
		if Input.is_action_just_pressed("interact"):
			start_conversation()

# =====================
# AREA SIGNALS
# =====================
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_near = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_near = false

# =====================
# CONVO START
# =====================
func start_conversation() -> void:
	if talking:
		return

	talking = true
	npc_log("Conversation started.")

	sprite.play("WALK")
	anim_player.play("COME")
	await anim_player.animation_finished
	sprite.play("IDLE")

	name_label.text = npc_name
	var initial_line = "Who are you? Why you knockin' on my door?"
	output_box.text = initial_line
	
	messages.clear()
	messages.append({
		"role": "system",
		"content": _system_prompt()
	})

	_set_talk_mode(TalkMode.NPC_SPEAKING)
	npc_log("Waiting for player to read...")
	await get_tree().create_timer(npc_think_time).timeout
	_set_talk_mode(TalkMode.PLAYER_TYPING)

# =====================
# PLAYER INPUT
# =====================
func _on_player_input(text: String) -> void:
	if talk_mode != TalkMode.PLAYER_TYPING:
		return

	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		return

	npc_log("Player sent: " + cleaned)
	_analyze_player_input(cleaned)

	input_box.text = ""
	output_box.text = "[...]" 
	_set_talk_mode(TalkMode.WAITING_AI)

	messages.append({
		"role": "user",
		"content": cleaned
	})

	_send_to_ai()

# =====================
# TRUST ANALYSIS
# =====================
func _convert_messages_to_google_format() -> Array:
	var contents = []
	var system_context = ""
	
	# Extract system message as context
	for msg in messages:
		if msg["role"] == "system":
			system_context = msg["content"]
			break
	
	# Convert user/assistant messages to Google format
	for msg in messages:
		if msg["role"] == "user":
			var user_text = msg["content"]
			# Add system context to first user message
			if system_context != "" and contents.is_empty():
				user_text = system_context + "\n\nUser: " + user_text
				system_context = ""  # Only add once
			
			contents.append({
				"role": "user",
				"parts": [{"text": user_text}]
			})
		elif msg["role"] == "assistant":
			contents.append({
				"role": "model",
				"parts": [{"text": msg["content"]}]
			})
	
	return contents

func _analyze_player_input(text: String) -> void:
	var t: String = text.to_lower()
	var old_trust = trust_level

	if !mentioned_money and (t.contains("money") or t.contains("pay") or t.contains("cash") or t.contains("$")):
		mentioned_money = true
	if !mentioned_safety and (t.contains("safe") or t.contains("radiation") or t.contains("danger") or t.contains("health")):
		mentioned_safety = true
	if !mentioned_community and (t.contains("village") or t.contains("community") or t.contains("town") or t.contains("everyone")):
		mentioned_community = true

	trust_level = int(mentioned_money) + int(mentioned_safety) + int(mentioned_community)

	if old_trust != trust_level:
		npc_log("Trust Level updated to: %d/3" % trust_level)

# =====================
# AI REQUEST
# =====================
func _send_to_ai() -> void:
	npc_log("Sending AI request...")
	
	var body: Dictionary = {
		"contents": _convert_messages_to_google_format(),
		"generationConfig": {}
	}

	var headers: PackedStringArray = [
		"Content-Type: application/json"
	]

	var error_code = http.request(
		"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent?key=" + api_key,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)

	if error_code != OK:
		npc_log("HTTP Request failed with error: %d" % error_code)
		output_box.text = "[Connection Error]"
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return

	http.request_completed.connect(_on_ai_response, CONNECT_ONE_SHOT)

# =====================
# AI RESPONSE
# =====================
func _on_ai_response(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	npc_log("Response Code: %d" % code)

	if code != 200:
		var error_body = body.get_string_from_utf8()
		npc_log("Error body: " + error_body)
		output_box.text = "[AI Error %d - Try different model]" % code
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return

	var body_string = body.get_string_from_utf8()
	npc_log("Response: " + body_string)
	
	var parsed: Variant = JSON.parse_string(body_string)

	if parsed == null or not parsed is Dictionary:
		npc_log("Failed to parse JSON")
		output_box.text = "[Parse Error]"
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return

	var json: Dictionary = parsed as Dictionary
	
	# Google AI Studio response format
	if not json.has("candidates") or json["candidates"].is_empty():
		npc_log("No candidates in response")
		output_box.text = "[No Response]"
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return

	var candidate = json["candidates"][0]
	if not candidate.has("content") or not candidate["content"].has("parts"):
		npc_log("Invalid response structure")
		output_box.text = "[Invalid Response]"
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return
	
	var parts = candidate["content"]["parts"]
	if parts.is_empty() or not parts[0].has("text"):
		npc_log("No text in response")
		output_box.text = "[No Text]"
		await get_tree().create_timer(2.0).timeout
		_set_talk_mode(TalkMode.PLAYER_TYPING)
		return
	
	var reply: String = str(parts[0]["text"]).strip_edges()
	
	if reply.is_empty():
		reply = "..."

	npc_log("AI Reply: " + reply)

	# Check for DONE command
	if reply.findn("DONE") != -1:
		if trust_level < 3:
			reply = "You talkin' big, but I don't trust you yet."
			npc_log("DONE detected but trust too low (%d/3)" % trust_level)
		else:
			_handle_convinced()
			return

	messages.append({ "role": "assistant", "content": reply })

	output_box.text = reply
	_set_talk_mode(TalkMode.NPC_SPEAKING)

	# Dynamic wait time based on message length
	var dynamic_wait_time = _calculate_read_time(reply)
	npc_log("Waiting %0.1f seconds for player to read..." % dynamic_wait_time)
	await get_tree().create_timer(dynamic_wait_time).timeout
	_set_talk_mode(TalkMode.PLAYER_TYPING)

# =====================
# CONVINCED
# =====================
func _calculate_read_time(text: String) -> float:
	var length = text.length()
	
	if length < 50:
		return 3.0  # Short messages: 3 seconds
	elif length < 100:
		return 5.0  # Medium messages: 5 seconds
	elif length < 150:
		return 7.0  # Long messages: 7 seconds
	else:
		return 9.0  # Very long messages: 9 seconds

func _handle_convinced() -> void:
	convinced = true
	talking = false
	npc_log("Convinced! Trust level: %d/3" % trust_level)

	output_box.text = "…Alright. I'll hear you out. For my kids."
	_set_talk_mode(TalkMode.NPC_SPEAKING)

	await get_tree().create_timer(3.0).timeout
	_set_talk_mode(TalkMode.NONE)

	sprite.play("WALK")
	anim_player.play("GO")
	await anim_player.animation_finished
	sprite.play("IDLE")

# =====================
# UI STATE MANAGEMENT
# =====================
func _set_talk_mode(mode: TalkMode) -> void:
	talk_mode = mode

	match mode:
		TalkMode.NONE:
			char1_node.visible = false
			input_node.visible = false
			output_node.visible = false
			input_box.editable = false

		TalkMode.NPC_SPEAKING:
			char1_node.visible = true
			output_node.visible = true
			input_node.visible = false
			input_box.editable = false

		TalkMode.PLAYER_TYPING:
			char1_node.visible = true
			input_node.visible = true
			output_node.visible = false
			input_box.editable = true
			input_box.grab_focus()

		TalkMode.WAITING_AI:
			char1_node.visible = true
			output_node.visible = true
			input_node.visible = false
			input_box.editable = false

# =====================
# SYSTEM PROMPT
# =====================
func _system_prompt() -> String:
	var knowledge: String = (
		"You know they represent a company."
		if trust_level >= 3
		else "You are suspicious of them."
	)

	return """You are %s, a %d-year-old villager.

YOUR LIFE:
- Family: %s
- Fear: %s
- Dream: %s

CURRENT STATE:
%s

RULES:
- Speak naturally (ain't, can't, don't).
- Keep responses short (under 30 words).
- If the stranger says little, be impatient.

Only say "DONE" when you fully trust them (Trust Level 3).""" % [
		npc_name, npc_age, npc_family, npc_fear, npc_dream, knowledge
	]
