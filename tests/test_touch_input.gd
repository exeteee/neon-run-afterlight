extends SceneTree

func _initialize() -> void:
    call_deferred("_run_touch_tests")


func _run_touch_tests() -> void:
    var packed_scene: PackedScene = load("res://scenes/main.tscn")
    assert(packed_scene != null, "Main game scene could not be loaded")
    var game: Node = packed_scene.instantiate()
    root.add_child(game)
    await process_frame
    game.set("mode", "running")

    var swipe_origins: Array[Vector2] = [
        Vector2(70.0, 170.0),
        Vector2(360.0, 620.0),
        Vector2(650.0, 1110.0)
    ]
    for origin in swipe_origins:
        _reset_runner_input(game)
        _send_swipe(game, origin, origin + Vector2(0.0, -92.0))
        assert(bool(game.get("jump_active")), "Up-swipe did not jump from " + str(origin))

    _reset_runner_input(game)
    _send_swipe(game, Vector2(560.0, 260.0), Vector2(635.0, 260.0))
    assert(int(game.get("target_lane")) == 2, "Right swipe did not change to the right lane")

    _reset_runner_input(game)
    _send_swipe(game, Vector2(170.0, 560.0), Vector2(90.0, 560.0))
    assert(int(game.get("target_lane")) == 0, "Left swipe did not change to the left lane")

    _reset_runner_input(game)
    _send_swipe(game, Vector2(340.0, 490.0), Vector2(340.0, 580.0))
    assert(float(game.get("slide_timer")) > 0.0, "Down swipe did not start a slide")

    game.queue_free()
    await process_frame
    game = null
    packed_scene = null
    await process_frame
    print("full-screen touch input passed: up/down/left/right at multiple screen positions")
    quit(0)


func _reset_runner_input(game: Node) -> void:
    game.set("jump_active", false)
    game.set("player_height", 0.0)
    game.set("jump_velocity", 0.0)
    game.set("slide_timer", 0.0)
    game.set("target_lane", 1)
    game.set("touch_active", false)


func _send_swipe(game: Node, start_position: Vector2, end_position: Vector2) -> void:
    var touch_down := InputEventScreenTouch.new()
    touch_down.index = 0
    touch_down.position = start_position
    touch_down.pressed = true
    game.call("_input", touch_down)

    var touch_up := InputEventScreenTouch.new()
    touch_up.index = 0
    touch_up.position = end_position
    touch_up.pressed = false
    game.call("_input", touch_up)
