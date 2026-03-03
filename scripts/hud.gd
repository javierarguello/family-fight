extends CanvasLayer

@export var player1_path: NodePath
@export var player2_path: NodePath

var _player1: CharacterBody2D
var _player2: CharacterBody2D

@onready var bar_p1: ProgressBar = $MarginContainer/HBoxContainer/P1/Bar
@onready var bar_p2: ProgressBar = $MarginContainer/HBoxContainer/P2/Bar
@onready var name_p1: Label = $MarginContainer/HBoxContainer/P1/Name
@onready var name_p2: Label = $MarginContainer/HBoxContainer/P2/Name


func _ready() -> void:
	_player1 = get_node_or_null(player1_path) as CharacterBody2D
	_player2 = get_node_or_null(player2_path) as CharacterBody2D

	if _player1:
		bar_p1.max_value = _player1.max_stamina
		bar_p1.value = _player1.stamina
		name_p1.text = _player1.get_character_name()

	if _player2:
		bar_p2.max_value = _player2.max_stamina
		bar_p2.value = _player2.stamina
		name_p2.text = _player2.get_character_name()


func _process(_delta: float) -> void:
	if _player1:
		bar_p1.value = _player1.stamina
	if _player2:
		bar_p2.value = _player2.stamina
