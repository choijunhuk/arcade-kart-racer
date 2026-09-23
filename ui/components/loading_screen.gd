extends Control

## Themed loading card shown by TransitionOverlay: animated menu backdrop,
## title, a slanted progress bar (the `Progress` node the overlay drives) and
## one random racing tip.

const TIPS: Array[String] = [
	"Hold drift through a corner until the sparks turn magenta for the biggest boost.",
	"Press accelerate just as GO appears for a rocket start.",
	"Boost pads stack with a mini-turbo — line them up.",
	"Slipstream behind a rival to close the gap, then pull out and pass.",
	"An Aegis Bubble blocks one hit; save it for the final straight.",
]


func _ready() -> void:
	($Tip as Label).text = TIPS[randi() % TIPS.size()]
