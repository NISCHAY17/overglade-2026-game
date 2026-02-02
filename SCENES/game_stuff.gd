extends Node

# Simple counter
var convinced_count: int = 0

# Add one to counter
func add_convinced() -> void:
	convinced_count += 1
	print("Convinced: ", convinced_count)
