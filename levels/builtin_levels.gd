class_name BuiltinLevels
extends RefCounted
## Built-in levels. Same dictionary format as the JSON files the editor saves to user://levels/.
##
## Coordinates are in the 1280x720 play area, y grows downwards.
## Angles are degrees: 0 = right, -90 = up. Behaviours are evaluated from tick 0 on
## every (re)start, so each level plays out identically for everyone.

const LEVELS := [
	{
		"format": 1, "id": "builtin_01", "name": "First Shot", "author": "BarrelBounce",
		"cannons": [
			{"x": 160.0, "y": 560.0, "angle": -40.0, "type": "normal", "behaviors": []},
		],
		"finish": {"x": 700.0, "y": 300.0, "w": 60.0, "h": 360.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_02", "name": "Catch Me", "author": "BarrelBounce",
		"cannons": [
			{"x": 140.0, "y": 580.0, "angle": -55.0, "type": "normal", "behaviors": []},
			{"x": 420.0, "y": 380.0, "angle": -20.0, "type": "normal", "behaviors": []},
		],
		"finish": {"x": 1000.0, "y": 200.0, "w": 60.0, "h": 400.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_03", "name": "Spin Cycle", "author": "BarrelBounce",
		"cannons": [
			{"x": 200.0, "y": 560.0, "angle": -90.0, "type": "normal", "behaviors": [
				{"type": "rotate", "speed": 90.0}]},
		],
		"finish": {"x": 760.0, "y": 150.0, "w": 60.0, "h": 450.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_04", "name": "Elevator", "author": "BarrelBounce",
		"cannons": [
			{"x": 150.0, "y": 600.0, "angle": -30.0, "type": "normal", "behaviors": []},
			{"x": 640.0, "y": 600.0, "angle": -60.0, "type": "normal", "behaviors": [
				{"type": "move", "dir": "up", "range": 250.0, "period": 3.0}]},
		],
		"finish": {"x": 1080.0, "y": 100.0, "w": 60.0, "h": 500.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_05", "name": "Blink", "author": "BarrelBounce",
		"cannons": [
			{"x": 120.0, "y": 620.0, "angle": -50.0, "type": "weak", "behaviors": []},
			{"x": 260.0, "y": 520.0, "angle": -10.0, "type": "dash", "behaviors": [
				{"type": "sweep", "from": -30.0, "to": 30.0, "period": 2.0}]},
			{"x": 820.0, "y": 540.0, "angle": -35.0, "type": "normal", "behaviors": []},
		],
		"finish": {"x": 1150.0, "y": 100.0, "w": 60.0, "h": 560.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_06", "name": "Orbit", "author": "BarrelBounce",
		"cannons": [
			{"x": 120.0, "y": 620.0, "angle": -50.0, "type": "normal", "behaviors": []},
			{"x": 560.0, "y": 330.0, "angle": -60.0, "type": "double", "behaviors": [
				{"type": "orbit", "radius": 110.0, "period": 4.0, "clockwise": true}]},
		],
		"finish": {"x": 1150.0, "y": 80.0, "w": 50.0, "h": 560.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_07", "name": "Hot Heads", "author": "BarrelBounce",
		"cannons": [
			{"x": 140.0, "y": 600.0, "angle": 0.0, "type": "normal", "behaviors": [
				{"type": "rotate", "speed": -120.0}]},
			{"x": 400.0, "y": 500.0, "angle": -30.0, "type": "auto", "behaviors": [
				{"type": "move", "dir": "right", "range": 300.0, "period": 2.5}]},
			{"x": 1000.0, "y": 440.0, "angle": -100.0, "type": "bubble", "behaviors": [
				{"type": "sweep", "from": -40.0, "to": 40.0, "period": 1.5}]},
		],
		"finish": {"x": 600.0, "y": 160.0, "w": 240.0, "h": 50.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_08", "name": "Bertha's Choice", "author": "BarrelBounce",
		"cannons": [
			{"x": 640.0, "y": 650.0, "angle": -90.0, "type": "strong", "behaviors": [
				{"type": "sweep", "from": -70.0, "to": 70.0, "period": 3.0}]},
			{"x": 200.0, "y": 250.0, "angle": -90.0, "type": "bubble", "behaviors": [
				{"type": "orbit", "radius": 80.0, "period": 2.0, "clockwise": false}]},
			{"x": 1080.0, "y": 250.0, "angle": 180.0, "type": "weak", "behaviors": [
				{"type": "rotate", "speed": -60.0}]},
		],
		"finish": {"x": 100.0, "y": 40.0, "w": 120.0, "h": 90.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_09", "name": "Two-Step", "author": "BarrelBounce",
		"cannons": [
			{"x": 160.0, "y": 600.0, "angle": -45.0, "type": "normal", "behaviors": []},
			{"x": 620.0, "y": 520.0, "angle": -40.0, "type": "normal", "behaviors": [
				{"type": "move", "dir": "up", "range": 220.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "right", "range": 220.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "down", "range": 220.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "left", "range": 220.0, "period": 2.0, "seq": true, "duration": 1.0}]},
		],
		"finish": {"x": 1150.0, "y": 100.0, "w": 60.0, "h": 500.0},
		"start": 0,
	},
	{
		"format": 1, "id": "builtin_10", "name": "The Long Haul", "author": "BarrelBounce",
		"width": 3400.0, "height": 900.0, "background": "sunset",
		"cannons": [
			{"x": 150.0, "y": 800.0, "angle": -45.0, "type": "normal", "behaviors": []},
			{"x": 560.0, "y": 650.0, "angle": -45.0, "type": "strong", "behaviors": [
				{"type": "sweep", "from": -25.0, "to": 25.0, "period": 4.0}]},
			{"x": 1050.0, "y": 350.0, "angle": -10.0, "type": "double", "behaviors": []},
			{"x": 1750.0, "y": 420.0, "angle": -60.0, "type": "bubble", "behaviors": [
				{"type": "move", "dir": "up", "range": 150.0, "period": 4.0}]},
			{"x": 2050.0, "y": 60.0, "angle": 30.0, "type": "dash", "behaviors": [
				{"type": "sweep", "from": -20.0, "to": 20.0, "period": 2.0}]},
			{"x": 2500.0, "y": 480.0, "angle": -45.0, "type": "normal", "behaviors": [
				{"type": "move", "dir": "up", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "right", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "down", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "left", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0}]},
			{"x": 2950.0, "y": 300.0, "angle": -75.0, "type": "auto", "behaviors": [
				{"type": "rotate", "speed": 90.0}]},
		],
		"finish": {"x": 3250.0, "y": 100.0, "w": 60.0, "h": 600.0},
		"start": 0,
	},
]
