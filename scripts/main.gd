extends Node3D

# NEON RUN: AFTERLIGHT — core game controller.
# All gameplay is offline. World chunks and hazards are recycled to keep memory stable.

const SAVE_PATH := "user://afterlight_profile.json"
const SEGMENT_LENGTH := 22.0
const PLAYER_Z := 0.0
const LANE_X := [-2.85, 0.0, 2.85]
const MAX_SEGMENTS := 10
const BASE_SPEED := 14.0
const MAX_SPEED := 27.5
const ZONE_LENGTH := 1900.0

const ZONE_NAMES := ["НЕОНОВАЯ НАБЕРЕЖНАЯ", "НЕБЕСНАЯ ЖЕЛЕЗНАЯ ДОРОГА", "ЯДРО МЕГАПОЛИСА"]
const ZONE_COLORS := [
    [Color("#101f49"), Color("#087f9d"), Color("#ef6b3c"), Color("#20e2f3")],
    [Color("#1c164a"), Color("#5544a4"), Color("#ff8c42"), Color("#8f77ff")],
    [Color("#071d2d"), Color("#0c6d70"), Color("#f8c15c"), Color("#27f4b1")]
]

const DIFFICULTIES := [
    {"name": "СПОКОЙНЫЙ", "speed": 0.88, "density": 0.78, "reward": 0.85},
    {"name": "НЕОНОВЫЙ", "speed": 1.0, "density": 1.0, "reward": 1.0},
    {"name": "ШТОРМ", "speed": 1.13, "density": 1.26, "reward": 1.35}
]

const UPGRADE_DATA := {
    "shield": {"name": "АВАРИЙНЫЙ ЩИТ", "description": "Поглощает одно столкновение за забег", "costs": [180, 420, 850]},
    "flux": {"name": "ИМПУЛЬСНЫЙ МОДУЛЬ", "description": "Увеличивает длительность энергетического рывка", "costs": [160, 380, 760]},
    "magnet": {"name": "МАГНИТНЫЙ СБОРЩИК", "description": "Притягивает осколки энергии и монеты", "costs": [140, 340, 680]}
}

var rng := RandomNumberGenerator.new()
var profile: Dictionary = {
    "coins": 0,
    "best_distance": 0,
    "best_score": 0,
    "runs": 0,
    "difficulty": 1,
    "volume": 0.72,
    "upgrades": {"shield": 0, "flux": 0, "magnet": 0},
    "stats": {"total_coins": 0, "total_pulses": 0, "total_distance": 0},
    "missions_claimed": []
}

var mode := "menu"
var world_root: Node3D
var runner_root: Node3D
var runner_body: Node3D
var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var camera_3d: Camera3D
var world_environment: WorldEnvironment
var segments: Array[Node3D] = []
var obstacles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var ui_layer: CanvasLayer
var ui_root: Control
var hud_distance: Label
var hud_score: Label
var hud_coins: Label
var hud_zone: Label
var hud_energy: ProgressBar
var hud_energy_text: Label
var pause_button: Button

var audio_music: AudioStreamPlayer
var audio_sfx: Array[AudioStreamPlayer] = []
var sfx_cursor := 0

var target_lane := 1
var current_lane_float := 1.0
var jump_velocity := 0.0
var player_height := 0.0
var jump_active := false
var slide_timer := 0.0
var run_time := 0.0
var distance_m := 0.0
var run_score := 0
var run_coins := 0
var run_cells := 0
var pulses_used := 0
var speed := BASE_SPEED
var energy := 0.0
var pulse_timer := 0.0
var shield_charges := 0
var magnet_timer := 0.0
var boost_timer := 0.0
var invulnerability_timer := 0.0
var last_zone := -1
var touch_start := Vector2.ZERO
var touch_active := false
var swipe_min_distance := 52.0
var run_result_reason := "СТОЛКНОВЕНИЕ"
var last_run_distance := 0
var last_run_score := 0
var last_run_coins := 0
var new_mission_rewards: Array[String] = []

var menu_difficulty: OptionButton
var settings_volume: HSlider
var shop_balance_label: Label
var shop_item_labels: Dictionary = {}


func _ready() -> void:
    rng.randomize()
    Engine.max_fps = 60
    _load_profile()
    _build_world()
    _build_runner()
    _build_audio()
    _build_ui_root()
    _show_menu()
    _update_audio_volume()


func _process(delta: float) -> void:
    if mode != "running":
        return
    var dt := minf(delta, 0.05)
    run_time += dt
    var difficulty: Dictionary = DIFFICULTIES[int(profile["difficulty"])]
    var ramp := minf(distance_m * 0.00135, 7.0)
    speed = minf(MAX_SPEED, (BASE_SPEED + ramp) * float(difficulty["speed"]))
    if boost_timer > 0.0:
        boost_timer = maxf(0.0, boost_timer - dt)
    if magnet_timer > 0.0:
        magnet_timer = maxf(0.0, magnet_timer - dt)
    if pulse_timer > 0.0:
        pulse_timer = maxf(0.0, pulse_timer - dt)
    if invulnerability_timer > 0.0:
        invulnerability_timer = maxf(0.0, invulnerability_timer - dt)

    var effective_speed := speed * (1.18 if boost_timer > 0.0 else 1.0)
    distance_m += effective_speed * dt * 0.82
    run_score = int(distance_m * 1.15) + run_coins * 12 + pulses_used * 35

    _update_runner(dt)
    _update_segments(dt, effective_speed)
    _update_pickups(dt)
    _check_collisions()
    _update_zone_theme()
    _update_hud()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        if mode == "running":
            _pause_run()
        elif mode == "paused":
            _resume_run()
        elif mode == "shop" or mode == "settings":
            _show_menu()
        return
    if mode != "running":
        return
    if event is InputEventScreenTouch:
        if event.pressed:
            touch_start = event.position
            touch_active = true
        elif touch_active:
            touch_active = false
            _interpret_swipe(event.position - touch_start)
    elif event is InputEventScreenDrag and touch_active:
        var drag := event.position - touch_start
        if drag.length() > swipe_min_distance:
            _interpret_swipe(drag)
            touch_start = event.position
    elif event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_LEFT, KEY_A:
                _change_lane(-1)
            KEY_RIGHT, KEY_D:
                _change_lane(1)
            KEY_UP, KEY_W, KEY_SPACE:
                _jump()
            KEY_DOWN, KEY_S:
                _slide()
            KEY_SHIFT, KEY_E:
                _activate_pulse()


func _interpret_swipe(delta: Vector2) -> void:
    if delta.length() < swipe_min_distance:
        return
    if absf(delta.x) > absf(delta.y):
        _change_lane(1 if delta.x > 0.0 else -1)
    elif delta.y < 0.0:
        _jump()
    else:
        _slide()


# -----------------------------------------------------------------------------
# Scene and world construction
# -----------------------------------------------------------------------------

func _build_world() -> void:
    world_root = Node3D.new()
    world_root.name = "World"
    add_child(world_root)

    world_environment = WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("#070d22")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("#7184b9")
    environment.ambient_light_energy = 0.65
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.glow_enabled = true
    environment.glow_intensity = 0.55
    environment.glow_bloom = 0.12
    environment.fog_enabled = true
    environment.fog_light_color = Color("#172b52")
    environment.fog_density = 0.008
    world_environment.environment = environment
    add_child(world_environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-42.0, -24.0, 0.0)
    sun.light_energy = 0.72
    sun.light_color = Color("#9ab9ff")
    sun.shadow_enabled = false
    add_child(sun)

    camera_3d = Camera3D.new()
    camera_3d.name = "RunnerCamera"
    camera_3d.position = Vector3(0.0, 6.5, 10.5)
    camera_3d.fov = 62.0
    camera_3d.current = true
    camera_3d.look_at(Vector3(0.0, 1.2, -17.0), Vector3.UP)
    add_child(camera_3d)

    for index in range(MAX_SEGMENTS):
        var segment := _create_segment(-11.0 - float(index) * SEGMENT_LENGTH, index == 0)
        segments.append(segment)


func _build_runner() -> void:
    runner_root = Node3D.new()
    runner_root.name = "Courier"
    runner_root.position = Vector3(0.0, 0.0, PLAYER_Z)
    add_child(runner_root)

    runner_body = Node3D.new()
    runner_body.name = "AnimatedBody"
    runner_body.position.y = 0.04
    runner_root.add_child(runner_body)

    var suit := _material(Color("#101a31"), 0.22, 0.28)
    var armor := _material(Color("#263d5b"), 0.42, 0.45)
    var cyan := _material(Color("#32e9ff"), 0.35, 0.18, true, 1.8)
    var orange := _material(Color("#ff8738"), 0.28, 0.2, true, 1.4)
    var visor := _material(Color("#8df9ff"), 0.1, 0.1, true, 2.2)

    _add_capsule(runner_body, 0.35, 0.82, Vector3(0.0, 1.18, 0.0), suit)
    _add_box(runner_body, Vector3(0.66, 0.4, 0.26), Vector3(0.0, 1.22, -0.22), armor)
    _add_sphere(runner_body, 0.27, Vector3(0.0, 1.88, 0.02), armor)
    _add_box(runner_body, Vector3(0.39, 0.13, 0.12), Vector3(0.0, 1.9, 0.255), visor)
    _add_box(runner_body, Vector3(0.26, 0.42, 0.28), Vector3(0.0, 1.26, -0.35), orange)
    _add_box(runner_body, Vector3(0.13, 0.5, 0.06), Vector3(0.0, 1.27, -0.51), cyan)
    _add_box(runner_body, Vector3(0.72, 0.09, 0.13), Vector3(0.0, 0.84, 0.0), cyan)

    left_arm = _build_limb(runner_body, Vector3(-0.43, 1.46, 0.0), 0.14, 0.56, armor)
    right_arm = _build_limb(runner_body, Vector3(0.43, 1.46, 0.0), 0.14, 0.56, armor)
    left_leg = _build_limb(runner_body, Vector3(-0.19, 0.57, 0.0), 0.16, 0.66, suit)
    right_leg = _build_limb(runner_body, Vector3(0.19, 0.57, 0.0), 0.16, 0.66, suit)


func _build_limb(parent: Node3D, pivot: Vector3, radius: float, height: float, material: Material) -> Node3D:
    var limb := Node3D.new()
    limb.position = pivot
    parent.add_child(limb)
    _add_capsule(limb, radius, height, Vector3(0.0, -height * 0.30, 0.0), material)
    var glow := _material(Color("#30dff4"), 0.35, 0.2, true, 0.8)
    _add_box(limb, Vector3(radius * 1.65, 0.06, radius * 1.7), Vector3(0.0, -height * 0.46, 0.0), glow)
    return limb


func _create_segment(z_position: float, safe_start: bool = false) -> Node3D:
    var segment := Node3D.new()
    segment.name = "TrackSegment"
    segment.position.z = z_position
    world_root.add_child(segment)

    var zone_index := int(floor(maxf(distance_m, 0.0) / ZONE_LENGTH)) % 3
    var palette: Array = ZONE_COLORS[zone_index]
    var road_mat := _material(palette[0], 0.48, 0.22)
    var rail_mat := _material(palette[1], 0.45, 0.22, true, 0.65)
    var accent_mat := _material(palette[3], 0.28, 0.18, true, 1.65)
    var warm_mat := _material(palette[2], 0.26, 0.22, true, 1.35)

    _add_box(segment, Vector3(9.2, 0.52, SEGMENT_LENGTH + 0.5), Vector3(0.0, -0.30, 0.0), road_mat)
    _add_box(segment, Vector3(0.08, 0.025, SEGMENT_LENGTH), Vector3(-1.43, -0.02, 0.0), accent_mat)
    _add_box(segment, Vector3(0.08, 0.025, SEGMENT_LENGTH), Vector3(1.43, -0.02, 0.0), accent_mat)
    _add_box(segment, Vector3(0.16, 0.30, SEGMENT_LENGTH), Vector3(-4.52, 0.0, 0.0), rail_mat)
    _add_box(segment, Vector3(0.16, 0.30, SEGMENT_LENGTH), Vector3(4.52, 0.0, 0.0), rail_mat)
    _add_box(segment, Vector3(0.10, 0.08, SEGMENT_LENGTH), Vector3(-4.4, 0.22, 0.0), warm_mat)
    _add_box(segment, Vector3(0.10, 0.08, SEGMENT_LENGTH), Vector3(4.4, 0.22, 0.0), warm_mat)

    for stripe_index in range(4):
        var stripe_z := -8.2 + float(stripe_index) * 5.4
        _add_box(segment, Vector3(0.42, 0.035, 0.11), Vector3(-3.0, -0.02, stripe_z), warm_mat)
        _add_box(segment, Vector3(0.42, 0.035, 0.11), Vector3(3.0, -0.02, stripe_z), warm_mat)

    _add_city_decor(segment, zone_index, palette)
    if not safe_start:
        _populate_segment(segment, palette)
    return segment


func _add_city_decor(segment: Node3D, zone_index: int, palette: Array) -> void:
    var building_colors := [Color("#172c55"), Color("#20254e"), Color("#123e50"), Color("#2a2650")]
    for side in [-1.0, 1.0]:
        for b in range(2):
            var height := rng.randf_range(7.0, 17.0) * (1.12 if zone_index == 2 else 1.0)
            var width := rng.randf_range(2.4, 3.5)
            var depth := rng.randf_range(7.0, 10.0)
            var x := side * rng.randf_range(7.2, 10.5)
            var z := rng.randf_range(-8.0, 8.0)
            var base := _material(building_colors[rng.randi_range(0, building_colors.size() - 1)], 0.35, 0.32)
            var tower := _add_box(segment, Vector3(width, height, depth), Vector3(x, height * 0.5 - 0.1, z), base)
            tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            var glow_color: Color = palette[3] if b == 0 else palette[2]
            var window_mat := _material(glow_color, 0.25, 0.18, true, 1.2)
            for floor_index in range(2, int(height / 2.4)):
                if rng.randf() < 0.65:
                    var wy := float(floor_index) * 2.0
                    _add_box(segment, Vector3(width * 0.56, 0.10, 0.06), Vector3(x, wy, z - depth * 0.51 - 0.035), window_mat)
            var roof_bar := _add_box(segment, Vector3(width * 0.72, 0.12, 0.12), Vector3(x, height + 0.1, z), window_mat)
            roof_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    var overhead_mat := _material(palette[1], 0.32, 0.25, true, 0.8)
    _add_box(segment, Vector3(0.12, 0.12, SEGMENT_LENGTH), Vector3(-5.5, 4.4, 0.0), overhead_mat)
    _add_box(segment, Vector3(0.12, 0.12, SEGMENT_LENGTH), Vector3(5.5, 4.4, 0.0), overhead_mat)
    if rng.randf() < 0.40:
        _add_box(segment, Vector3(11.0, 0.10, 0.10), Vector3(0.0, 4.35, -rng.randf_range(-6.0, 6.0)), overhead_mat)


func _populate_segment(segment: Node3D, palette: Array) -> void:
    var difficulty: Dictionary = DIFFICULTIES[int(profile["difficulty"])]
    var density: float = float(difficulty["density"])
    var row_positions := [-7.2, 0.0, 7.2]
    for row_index in range(row_positions.size()):
        var blocked_lane := rng.randi_range(0, 2)
        var obstacle_kind := _choose_obstacle_kind()
        var blocked_lanes: Array[int] = [blocked_lane]
        if rng.randf() < 0.78 * density:
            _spawn_obstacle(segment, blocked_lane, row_positions[row_index], obstacle_kind, palette)
        var second_chance := 0.16 * density
        if rng.randf() < second_chance:
            var second_lane := (blocked_lane + rng.randi_range(1, 2)) % 3
            blocked_lanes.append(second_lane)
            _spawn_obstacle(segment, second_lane, row_positions[row_index], _choose_obstacle_kind(), palette)

        var safe_lane := 0
        for candidate_lane in range(3):
            if not blocked_lanes.has(candidate_lane):
                safe_lane = candidate_lane
                break
        for coin_index in range(3):
            var coin_z := row_positions[row_index] + float(coin_index - 1) * 1.55
            _spawn_pickup(segment, safe_lane, coin_z, "coin", palette)
        if row_index == 1 and rng.randf() < 0.82:
            _spawn_pickup(segment, safe_lane, row_positions[row_index] - 0.6, "cell", palette)
        if row_index == 2 and rng.randf() < 0.12:
            _spawn_pickup(segment, safe_lane, row_positions[row_index] - 2.0, "powerup", palette)


func _choose_obstacle_kind() -> String:
    var roll := rng.randf()
    if roll < 0.28:
        return "crate"
    if roll < 0.49:
        return "beam"
    if roll < 0.72:
        return "train"
    if roll < 0.88:
        return "spikes"
    return "phase_gate"


func _spawn_obstacle(segment: Node3D, lane: int, local_z: float, kind: String, palette: Array) -> void:
    var obstacle := Node3D.new()
    obstacle.name = "Hazard_" + kind
    obstacle.position = Vector3(LANE_X[lane], 0.0, local_z)
    segment.add_child(obstacle)
    var dark := _material(Color("#172138"), 0.34, 0.3)
    var orange := _material(Color("#ff793d"), 0.25, 0.2, true, 1.0)
    var cyan := _material(palette[3], 0.22, 0.2, true, 1.5)
    var glass := _material(Color("#4d7892"), 0.65, 0.12, true, 0.55)

    match kind:
        "crate":
            _add_box(obstacle, Vector3(1.72, 1.12, 1.05), Vector3(0.0, 0.58, 0.0), dark)
            _add_box(obstacle, Vector3(1.78, 0.13, 1.10), Vector3(0.0, 0.96, 0.0), orange)
            _add_box(obstacle, Vector3(0.12, 1.18, 1.14), Vector3(0.0, 0.58, 0.0), orange)
        "beam":
            _add_box(obstacle, Vector3(1.92, 0.28, 0.62), Vector3(0.0, 1.66, 0.0), orange)
            _add_box(obstacle, Vector3(0.17, 1.7, 0.62), Vector3(-0.88, 0.83, 0.0), dark)
            _add_box(obstacle, Vector3(0.17, 1.7, 0.62), Vector3(0.88, 0.83, 0.0), dark)
            _add_box(obstacle, Vector3(1.4, 0.08, 0.08), Vector3(0.0, 1.48, 0.34), orange)
        "train":
            _add_box(obstacle, Vector3(2.28, 2.72, 4.5), Vector3(0.0, 1.36, 0.0), dark)
            _add_box(obstacle, Vector3(1.78, 0.74, 0.08), Vector3(0.0, 1.82, 2.28), glass)
            _add_box(obstacle, Vector3(0.12, 2.5, 0.10), Vector3(-1.05, 1.36, 2.30), cyan)
            _add_box(obstacle, Vector3(0.12, 2.5, 0.10), Vector3(1.05, 1.36, 2.30), cyan)
            _add_box(obstacle, Vector3(0.52, 0.13, 0.08), Vector3(0.0, 0.28, 2.34), orange)
        "spikes":
            var spike_mesh := CylinderMesh.new()
            spike_mesh.top_radius = 0.02
            spike_mesh.bottom_radius = 0.70
            spike_mesh.height = 0.95
            var spike := MeshInstance3D.new()
            spike.mesh = spike_mesh
            spike.position = Vector3(0.0, 0.47, 0.0)
            spike.material_override = orange
            obstacle.add_child(spike)
            _add_box(obstacle, Vector3(1.85, 0.13, 0.95), Vector3(0.0, 0.08, 0.0), dark)
        "phase_gate":
            _add_box(obstacle, Vector3(0.16, 2.55, 0.20), Vector3(-0.88, 1.28, 0.0), cyan)
            _add_box(obstacle, Vector3(0.16, 2.55, 0.20), Vector3(0.88, 1.28, 0.0), cyan)
            _add_box(obstacle, Vector3(1.92, 0.16, 0.20), Vector3(0.0, 2.52, 0.0), cyan)
            _add_box(obstacle, Vector3(0.88, 0.12, 0.16), Vector3(0.0, 0.92, 0.0), orange)

    obstacles.append({"node": obstacle, "kind": kind, "lane": lane, "segment": segment, "resolved": false})


func _spawn_pickup(segment: Node3D, lane: int, local_z: float, kind: String, palette: Array) -> void:
    var item := Node3D.new()
    item.name = "Pickup_" + kind
    item.position = Vector3(LANE_X[lane], 0.9, local_z)
    segment.add_child(item)
    var material: Material
    var mesh: Mesh
    if kind == "coin":
        material = _material(Color("#ffd66a"), 0.55, 0.14, true, 1.25)
        var coin_mesh := CylinderMesh.new()
        coin_mesh.top_radius = 0.34
        coin_mesh.bottom_radius = 0.34
        coin_mesh.height = 0.12
        mesh = coin_mesh
    elif kind == "cell":
        material = _material(palette[3], 0.22, 0.18, true, 2.0)
        var cell_mesh := BoxMesh.new()
        cell_mesh.size = Vector3(0.36, 0.55, 0.36)
        mesh = cell_mesh
    else:
        material = _material(Color("#ff6bcf"), 0.22, 0.1, true, 1.8)
        var power_mesh := SphereMesh.new()
        power_mesh.radius = 0.34
        power_mesh.height = 0.68
        mesh = power_mesh
    var visual := MeshInstance3D.new()
    visual.mesh = mesh
    visual.material_override = material
    if kind == "coin":
        visual.rotation.x = deg_to_rad(90.0)
    item.add_child(visual)
    if kind != "coin":
        var core := _add_sphere(item, 0.11, Vector3(0.0, 0.0, 0.0), _material(Color("#ffffff"), 0.2, 0.1, true, 2.0))
        core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    pickups.append({"node": item, "kind": kind, "lane": lane, "segment": segment, "offset": rng.randf() * 5.0, "resolved": false})


func _update_segments(delta: float, effective_speed: float) -> void:
    var min_z := 100000.0
    for segment in segments:
        segment.position.z += effective_speed * delta
        min_z = minf(min_z, segment.position.z)
    for index in range(segments.size()):
        var old_segment := segments[index]
        if old_segment.position.z > 12.0:
            var new_z := min_z - SEGMENT_LENGTH
            _remove_segment_records(old_segment)
            var replacement := _create_segment(new_z)
            old_segment.queue_free()
            segments[index] = replacement
            min_z = new_z


func _remove_segment_records(segment: Node3D) -> void:
    for index in range(obstacles.size() - 1, -1, -1):
        if obstacles[index]["segment"] == segment:
            obstacles.remove_at(index)
    for index in range(pickups.size() - 1, -1, -1):
        if pickups[index]["segment"] == segment:
            pickups.remove_at(index)


func _update_zone_theme() -> void:
    var zone_index := int(floor(distance_m / ZONE_LENGTH)) % 3
    if zone_index == last_zone:
        return
    last_zone = zone_index
    world_environment.environment.background_color = [Color("#07142c"), Color("#160f36"), Color("#061f2a")][zone_index]
    world_environment.environment.fog_light_color = [Color("#132b4f"), Color("#211746"), Color("#0d3b3d")][zone_index]


# -----------------------------------------------------------------------------
# Runner controller, collision, and pickups
# -----------------------------------------------------------------------------

func _update_runner(delta: float) -> void:
    var target_x: float = LANE_X[target_lane]
    current_lane_float = lerpf(current_lane_float, float(target_lane), minf(1.0, delta * 13.0))
    runner_root.position.x = lerpf(runner_root.position.x, target_x, minf(1.0, delta * 15.0))

    if jump_active:
        jump_velocity -= 24.0 * delta
        player_height += jump_velocity * delta
        if player_height <= 0.0:
            player_height = 0.0
            jump_velocity = 0.0
            jump_active = false
    runner_root.position.y = player_height

    if slide_timer > 0.0:
        slide_timer = maxf(0.0, slide_timer - delta)
        runner_body.scale.y = 0.54
        runner_body.position.y = -0.28
    else:
        runner_body.scale.y = 1.0
        runner_body.position.y = 0.04

    var run_phase := run_time * 13.5
    if not jump_active and slide_timer <= 0.0:
        left_leg.rotation.x = sin(run_phase) * 0.56
        right_leg.rotation.x = -sin(run_phase) * 0.56
        left_arm.rotation.x = -sin(run_phase) * 0.38
        right_arm.rotation.x = sin(run_phase) * 0.38
    elif jump_active:
        left_leg.rotation.x = -0.35
        right_leg.rotation.x = 0.52
        left_arm.rotation.x = -0.72
        right_arm.rotation.x = -0.72
    else:
        left_leg.rotation.x = 0.12
        right_leg.rotation.x = 0.12
        left_arm.rotation.x = 0.2
        right_arm.rotation.x = 0.2

    runner_body.rotation.z = lerpf(runner_body.rotation.z, (float(target_lane) - current_lane_float) * 0.10, delta * 8.0)
    var pulse_glow := pulse_timer > 0.0
    if pulse_glow:
        runner_body.scale.x = 1.0 + sin(run_time * 28.0) * 0.045
        runner_body.scale.z = 1.0 + sin(run_time * 28.0) * 0.045
    else:
        runner_body.scale.x = 1.0
        runner_body.scale.z = 1.0


func _change_lane(direction: int) -> void:
    target_lane = clampi(target_lane + direction, 0, 2)


func _jump() -> void:
    if jump_active or slide_timer > 0.0:
        return
    jump_active = true
    jump_velocity = 9.1
    _play_sfx("jump")


func _slide() -> void:
    if jump_active:
        return
    slide_timer = 0.78
    _play_sfx("slide")


func _activate_pulse() -> void:
    if energy < 100.0 or pulse_timer > 0.0:
        return
    energy = 0.0
    var flux_level: int = int(profile["upgrades"]["flux"])
    pulse_timer = 1.05 + float(flux_level) * 0.30
    pulses_used += 1
    _play_sfx("pulse")


func _check_collisions() -> void:
    if invulnerability_timer > 0.0:
        return
    for index in range(obstacles.size()):
        var obstacle: Dictionary = obstacles[index]
        if obstacle["resolved"]:
            continue
        var node: Node3D = obstacle["node"]
        if not is_instance_valid(node):
            continue
        var z_distance := node.global_position.z - PLAYER_Z
        if z_distance > 1.0:
            obstacle["resolved"] = true
            node.visible = false
            obstacles[index] = obstacle
            continue
        if absf(z_distance) > 0.66:
            continue
        if absf(node.global_position.x - runner_root.position.x) > 1.05:
            continue
        var kind: String = obstacle["kind"]
        var safe := false
        if pulse_timer > 0.0:
            safe = true
        elif kind == "crate" or kind == "spikes":
            safe = jump_active and player_height > 0.68
        elif kind == "beam":
            safe = slide_timer > 0.10
        elif kind == "phase_gate":
            safe = false
        elif kind == "train":
            safe = false
        obstacle["resolved"] = true
        obstacles[index] = obstacle
        if not safe:
            _on_player_hit()
            return


func _on_player_hit() -> void:
    if shield_charges > 0:
        shield_charges -= 1
        invulnerability_timer = 1.25
        _play_sfx("powerup")
        return
    run_result_reason = "СТОЛКНОВЕНИЕ"
    _end_run()


func _update_pickups(delta: float) -> void:
    for index in range(pickups.size()):
        var pickup: Dictionary = pickups[index]
        if pickup["resolved"]:
            continue
        var node: Node3D = pickup["node"]
        if not is_instance_valid(node):
            pickup["resolved"] = true
            pickups[index] = pickup
            continue
        var z_distance := node.global_position.z - PLAYER_Z
        if z_distance > 1.0:
            pickup["resolved"] = true
            node.visible = false
            pickups[index] = pickup
            continue

        var kind: String = pickup["kind"]
        var magnet_active := magnet_timer > 0.0
        if magnet_active and (kind == "coin" or kind == "cell") and absf(z_distance) < 8.0:
            node.global_position.x = lerpf(node.global_position.x, runner_root.global_position.x, delta * 5.5)
        node.rotation.y += delta * (3.0 if kind == "coin" else 1.6)
        node.position.y = 0.9 + sin(run_time * 4.0 + float(pickup["offset"])) * 0.11
        var x_distance := absf(node.global_position.x - runner_root.position.x)
        if absf(z_distance) < 0.82 and (x_distance < 0.92 or magnet_active):
            pickup["resolved"] = true
            pickups[index] = pickup
            _collect_pickup(kind)
            node.visible = false


func _collect_pickup(kind: String) -> void:
    match kind:
        "coin":
            run_coins += 1
            _play_sfx("coin")
        "cell":
            run_cells += 1
            energy = minf(100.0, energy + 20.0)
            _play_sfx("powerup")
        "powerup":
            var roll := rng.randi_range(0, 2)
            if roll == 0:
                shield_charges = maxi(shield_charges, 1)
            elif roll == 1:
                magnet_timer = 7.0 + float(profile["upgrades"]["magnet"]) * 2.0
            else:
                boost_timer = 5.0
            _play_sfx("powerup")


# -----------------------------------------------------------------------------
# Progression and local save data
# -----------------------------------------------------------------------------

func _start_run() -> void:
    mode = "running"
    distance_m = 0.0
    _reset_track()
    run_time = 0.0
    run_score = 0
    run_coins = 0
    run_cells = 0
    pulses_used = 0
    energy = 10.0
    speed = BASE_SPEED
    target_lane = 1
    current_lane_float = 1.0
    runner_root.position = Vector3(0.0, 0.0, PLAYER_Z)
    jump_active = false
    jump_velocity = 0.0
    player_height = 0.0
    slide_timer = 0.0
    pulse_timer = 0.0
    magnet_timer = 0.0
    boost_timer = 0.0
    invulnerability_timer = 0.0
    shield_charges = 1 if int(profile["upgrades"]["shield"]) > 0 else 0
    last_zone = -1
    _play_sfx("button")
    _show_hud()
    if int(profile["runs"]) == 0:
        mode = "tutorial"
        _show_tutorial()


func _end_run() -> void:
    if mode != "running":
        return
    mode = "results"
    last_run_distance = int(distance_m)
    last_run_score = run_score
    last_run_coins = run_coins
    var difficulty: Dictionary = DIFFICULTIES[int(profile["difficulty"])]
    var earned := int(round(float(run_coins) * float(difficulty["reward"])))
    profile["coins"] = int(profile["coins"]) + earned
    profile["runs"] = int(profile["runs"]) + 1
    profile["best_distance"] = maxi(int(profile["best_distance"]), last_run_distance)
    profile["best_score"] = maxi(int(profile["best_score"]), last_run_score)
    var stats: Dictionary = profile["stats"]
    stats["total_coins"] = int(stats["total_coins"]) + run_coins
    stats["total_pulses"] = int(stats["total_pulses"]) + pulses_used
    stats["total_distance"] = int(stats["total_distance"]) + last_run_distance
    profile["stats"] = stats
    _check_missions()
    _save_profile()
    _play_sfx("crash")
    _show_results(earned)


func _check_missions() -> void:
    new_mission_rewards.clear()
    var claimed: Array = profile["missions_claimed"]
    var stats: Dictionary = profile["stats"]
    var missions := [
        {"id": "distance", "done": int(profile["best_distance"]) >= 1500, "reward": 100, "name": "ПЕРВЫЕ 1 500 МЕТРОВ"},
        {"id": "coins", "done": int(stats["total_coins"]) >= 250, "reward": 125, "name": "СОБРАТЬ 250 МОНЕТ"},
        {"id": "pulse", "done": int(stats["total_pulses"]) >= 18, "reward": 150, "name": "18 ЭНЕРГЕТИЧЕСКИХ РЫВКОВ"}
    ]
    for mission in missions:
        if bool(mission["done"]) and not claimed.has(mission["id"]):
            claimed.append(mission["id"])
            profile["coins"] = int(profile["coins"]) + int(mission["reward"])
            new_mission_rewards.append(str(mission["name"]) + "  +" + str(mission["reward"]))
    profile["missions_claimed"] = claimed


func _load_profile() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    file.close()
    if parsed is Dictionary:
        for key in parsed.keys():
            profile[key] = parsed[key]
    if not profile.has("upgrades") or not (profile["upgrades"] is Dictionary):
        profile["upgrades"] = {"shield": 0, "flux": 0, "magnet": 0}
    if not profile.has("stats") or not (profile["stats"] is Dictionary):
        profile["stats"] = {"total_coins": 0, "total_pulses": 0, "total_distance": 0}
    if not profile.has("missions_claimed") or not (profile["missions_claimed"] is Array):
        profile["missions_claimed"] = []
    profile["difficulty"] = clampi(int(profile.get("difficulty", 1)), 0, 2)
    profile["volume"] = clampf(float(profile.get("volume", 0.72)), 0.0, 1.0)


func _save_profile() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_warning("Unable to save profile: " + str(FileAccess.get_open_error()))
        return
    file.store_string(JSON.stringify(profile, "  "))
    file.close()


func _buy_upgrade(upgrade_id: String) -> void:
    var level: int = int(profile["upgrades"][upgrade_id])
    var costs: Array = UPGRADE_DATA[upgrade_id]["costs"]
    if level >= costs.size():
        _play_sfx("button")
        return
    var cost: int = int(costs[level])
    if int(profile["coins"]) < cost:
        _play_sfx("button")
        return
    profile["coins"] = int(profile["coins"]) - cost
    profile["upgrades"][upgrade_id] = level + 1
    _save_profile()
    _play_sfx("powerup")
    _show_shop()


# -----------------------------------------------------------------------------
# Audio
# -----------------------------------------------------------------------------

func _build_audio() -> void:
    audio_music = AudioStreamPlayer.new()
    audio_music.name = "OriginalAmbientMusic"
    var music_stream: AudioStreamWAV = load("res://audio/neon_ambience.wav")
    music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    audio_music.stream = music_stream
    audio_music.bus = "Master"
    add_child(audio_music)
    audio_music.play()

    for index in range(6):
        var player := AudioStreamPlayer.new()
        player.name = "SFX_" + str(index)
        player.bus = "Master"
        add_child(player)
        audio_sfx.append(player)


func _play_sfx(sound_name: String) -> void:
    if audio_sfx.is_empty():
        return
    var player: AudioStreamPlayer = audio_sfx[sfx_cursor]
    sfx_cursor = (sfx_cursor + 1) % audio_sfx.size()
    player.stream = load("res://audio/" + sound_name + ".wav")
    var base_volume := linear_to_db(maxf(float(profile["volume"]), 0.001))
    player.volume_db = base_volume + (-7.0 if sound_name == "coin" else -2.5)
    player.play()


func _update_audio_volume() -> void:
    var volume: float = clampf(float(profile["volume"]), 0.0, 1.0)
    var db := linear_to_db(maxf(volume, 0.001))
    if is_instance_valid(audio_music):
        audio_music.volume_db = db - 8.0
    for player in audio_sfx:
        player.volume_db = db - 2.5


# -----------------------------------------------------------------------------
# UI construction — scalable portrait mobile layout
# -----------------------------------------------------------------------------

func _build_ui_root() -> void:
    ui_layer = CanvasLayer.new()
    ui_layer.layer = 20
    add_child(ui_layer)
    ui_root = Control.new()
    ui_root.name = "UIRoot"
    ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(ui_root)


func _clear_ui() -> void:
    for child in ui_root.get_children():
        child.queue_free()
    hud_distance = null
    hud_score = null
    hud_coins = null
    hud_zone = null
    hud_energy = null
    hud_energy_text = null
    pause_button = null


func _make_background(parent: Control, darken: float = 0.48) -> void:
    var art := TextureRect.new()
    art.texture = load("res://assets/title_art.png")
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    parent.add_child(art)
    var shade := ColorRect.new()
    shade.color = Color(0.01, 0.025, 0.065, darken)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    parent.add_child(shade)


func _make_panel(parent: Control, top: float = 0.14, bottom: float = 0.88) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.anchor_left = 0.055
    panel.anchor_right = 0.945
    panel.anchor_top = top
    panel.anchor_bottom = bottom
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.015, 0.035, 0.085, 0.94)
    style.border_color = Color(0.07, 0.78, 0.95, 0.72)
    style.set_border_width_all(2)
    style.set_corner_radius_all(18)
    style.content_margin_left = 22.0
    style.content_margin_right = 22.0
    style.content_margin_top = 24.0
    style.content_margin_bottom = 24.0
    panel.add_theme_stylebox_override("panel", style)
    parent.add_child(panel)
    return panel


func _make_label(text: String, size: int = 22, color: Color = Color("#e6f8ff"), centered: bool = false) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 2)
    if centered:
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label


func _make_button(text: String, callback: Callable, primary: bool = false) -> Button:
    var button := Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(0.0, 58.0)
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 20)
    button.add_theme_color_override("font_color", Color("#f4fbff"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.0, 0.55, 0.71, 0.95) if primary else Color(0.035, 0.10, 0.19, 0.98)
    normal.border_color = Color("#36e9ff") if primary else Color("#315d7d")
    normal.set_border_width_all(2 if primary else 1)
    normal.set_corner_radius_all(12)
    normal.content_margin_left = 14.0
    normal.content_margin_right = 14.0
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.02, 0.72, 0.85, 1.0) if primary else Color(0.06, 0.19, 0.30, 1.0)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.02, 0.36, 0.52, 1.0)
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.pressed.connect(callback)
    return button


func _make_gap(parent: VBoxContainer, amount: float = 10.0) -> void:
    var gap := Control.new()
    gap.custom_minimum_size.y = amount
    parent.add_child(gap)


func _make_menu_header(vbox: VBoxContainer, subtitle: String) -> void:
    var title := _make_label("NEON RUN", 42, Color("#ffffff"), true)
    title.add_theme_color_override("font_outline_color", Color("#00cce8"))
    title.add_theme_constant_override("outline_size", 5)
    vbox.add_child(title)
    vbox.add_child(_make_label("AFTERLIGHT", 23, Color("#ff9a51"), true))
    _make_gap(vbox, 7.0)
    vbox.add_child(_make_label(subtitle, 15, Color("#a9d8e9"), true))


func _show_menu() -> void:
    mode = "menu"
    _clear_ui()
    _make_background(ui_root, 0.47)
    var panel := _make_panel(ui_root, 0.10, 0.91)
    var layout := VBoxContainer.new()
    layout.alignment = BoxContainer.ALIGNMENT_CENTER
    layout.add_theme_constant_override("separation", 12)
    panel.add_child(layout)
    _make_menu_header(layout, "ГОРОД НЕ СПИТ. ТВОЙ ЗАБЕГ НАЧИНАЕТСЯ СЕЙЧАС.")
    _make_gap(layout, 8.0)
    layout.add_child(_make_label("РЕКОРД  " + _format_number(int(profile["best_distance"])) + " м", 18, Color("#ffd67a"), true))
    layout.add_child(_make_label("МОНЕТЫ  " + _format_number(int(profile["coins"])), 16, Color("#8ceeff"), true))
    _make_gap(layout, 3.0)
    layout.add_child(_make_label("УРОВЕНЬ СЛОЖНОСТИ", 14, Color("#9dc5d9"), true))
    menu_difficulty = OptionButton.new()
    for difficulty in DIFFICULTIES:
        menu_difficulty.add_item(str(difficulty["name"]))
    menu_difficulty.select(int(profile["difficulty"]))
    menu_difficulty.custom_minimum_size = Vector2(0, 48)
    menu_difficulty.add_theme_font_size_override("font_size", 17)
    menu_difficulty.item_selected.connect(_on_difficulty_selected)
    layout.add_child(menu_difficulty)
    _make_gap(layout, 7.0)
    layout.add_child(_make_button("НАЧАТЬ ЗАБЕГ", _start_run, true))
    layout.add_child(_make_button("УЛУЧШЕНИЯ  /  МАСТЕРСКАЯ", _show_shop))
    layout.add_child(_make_button("НАСТРОЙКИ", _show_settings))
    _make_gap(layout, 7.0)
    var best_zone := "НЕОНОВАЯ НАБЕРЕЖНАЯ"
    if int(profile["best_distance"]) >= int(ZONE_LENGTH * 2.0):
        best_zone = "ЯДРО МЕГАПОЛИСА"
    elif int(profile["best_distance"]) >= int(ZONE_LENGTH):
        best_zone = "НЕБЕСНАЯ ЖЕЛЕЗНАЯ ДОРОГА"
    layout.add_child(_make_label("ОТКРЫТЫЙ РАЙОН: " + best_zone, 13, Color("#7fabc1"), true))
    layout.add_child(_make_label("ОФЛАЙН • ОДИНОЧНАЯ ИГРА", 12, Color("#5e8197"), true))


func _on_difficulty_selected(index: int) -> void:
    profile["difficulty"] = clampi(index, 0, 2)
    _save_profile()
    _play_sfx("button")


func _show_hud() -> void:
    _clear_ui()
    var top_panel := PanelContainer.new()
    top_panel.anchor_left = 0.035
    top_panel.anchor_right = 0.69
    top_panel.anchor_top = 0.025
    top_panel.anchor_bottom = 0.185
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.01, 0.035, 0.085, 0.86)
    style.border_color = Color(0.08, 0.69, 0.88, 0.65)
    style.set_border_width_all(1)
    style.set_corner_radius_all(13)
    style.content_margin_left = 13.0
    style.content_margin_right = 13.0
    style.content_margin_top = 8.0
    style.content_margin_bottom = 8.0
    top_panel.add_theme_stylebox_override("panel", style)
    ui_root.add_child(top_panel)
    var stats := VBoxContainer.new()
    stats.add_theme_constant_override("separation", 1)
    top_panel.add_child(stats)
    hud_distance = _make_label("0 м", 23, Color("#ffffff"))
    hud_score = _make_label("СЧЁТ  0", 16, Color("#ffd47c"))
    hud_coins = _make_label("МОНЕТЫ  0", 15, Color("#7cecff"))
    hud_zone = _make_label("НЕОНОВАЯ НАБЕРЕЖНАЯ", 11, Color("#9ec5d7"))
    stats.add_child(hud_distance)
    stats.add_child(hud_score)
    stats.add_child(hud_coins)
    stats.add_child(hud_zone)

    pause_button = _make_button("Ⅱ", _pause_run)
    pause_button.anchor_left = 0.78
    pause_button.anchor_right = 0.965
    pause_button.anchor_top = 0.035
    pause_button.anchor_bottom = 0.095
    pause_button.add_theme_font_size_override("font_size", 27)
    ui_root.add_child(pause_button)

    var energy_panel := PanelContainer.new()
    energy_panel.anchor_left = 0.045
    energy_panel.anchor_right = 0.68
    energy_panel.anchor_top = 0.895
    energy_panel.anchor_bottom = 0.96
    var energy_style := StyleBoxFlat.new()
    energy_style.bg_color = Color(0.01, 0.035, 0.085, 0.88)
    energy_style.border_color = Color("#1da8c9")
    energy_style.set_border_width_all(1)
    energy_style.set_corner_radius_all(12)
    energy_panel.add_theme_stylebox_override("panel", energy_style)
    ui_root.add_child(energy_panel)
    var energy_box := VBoxContainer.new()
    energy_box.add_theme_constant_override("separation", 0)
    energy_panel.add_child(energy_box)
    hud_energy_text = _make_label("ЭНЕРГИЯ  —  0%", 13, Color("#a9efff"))
    energy_box.add_child(hud_energy_text)
    hud_energy = ProgressBar.new()
    hud_energy.min_value = 0.0
    hud_energy.max_value = 100.0
    hud_energy.value = energy
    hud_energy.show_percentage = false
    hud_energy.custom_minimum_size.y = 12.0
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color("#1ddaf5")
    fill.set_corner_radius_all(6)
    hud_energy.add_theme_stylebox_override("fill", fill)
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color("#17324b")
    bg.set_corner_radius_all(6)
    hud_energy.add_theme_stylebox_override("background", bg)
    energy_box.add_child(hud_energy)

    var pulse_button := _make_button("ИМПУЛЬС", _activate_pulse, true)
    pulse_button.anchor_left = 0.72
    pulse_button.anchor_right = 0.96
    pulse_button.anchor_top = 0.875
    pulse_button.anchor_bottom = 0.96
    pulse_button.add_theme_font_size_override("font_size", 16)
    ui_root.add_child(pulse_button)
    var swipe_hint := _make_label("← / → ПОЛОСА     ↑ ПРЫЖОК     ↓ ПОДКАТ", 13, Color("#a9c8d7"), true)
    swipe_hint.anchor_left = 0.05
    swipe_hint.anchor_right = 0.95
    swipe_hint.anchor_top = 0.81
    swipe_hint.anchor_bottom = 0.86
    ui_root.add_child(swipe_hint)
    _update_hud()


func _update_hud() -> void:
    if not is_instance_valid(hud_distance):
        return
    hud_distance.text = _format_number(int(distance_m)) + " м"
    hud_score.text = "СЧЁТ  " + _format_number(run_score)
    hud_coins.text = "МОНЕТЫ  " + str(run_coins) + "    •    ОСКОЛКИ  " + str(run_cells)
    var zone_index := int(floor(distance_m / ZONE_LENGTH)) % 3
    hud_zone.text = ZONE_NAMES[zone_index]
    hud_energy.value = energy
    hud_energy_text.text = "ЭНЕРГИЯ  —  " + str(int(energy)) + "%" + ("   •   ИМПУЛЬС АКТИВЕН" if pulse_timer > 0.0 else "")


func _show_tutorial() -> void:
    var overlay := ColorRect.new()
    overlay.color = Color(0.01, 0.02, 0.05, 0.83)
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(overlay)
    var panel := _make_panel(ui_root, 0.28, 0.73)
    panel.anchor_left = 0.07
    panel.anchor_right = 0.93
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(box)
    box.add_child(_make_label("КАК ИГРАТЬ", 28, Color("#ffffff"), true))
    box.add_child(_make_label("Свайп влево или вправо — сменить полосу.\nСвайп вверх — перепрыгнуть ящик или шипы.\nСвайп вниз — проскользить под балкой.\nСобирай осколки, чтобы зарядить ИМПУЛЬС.\nНажми ИМПУЛЬС, чтобы пережить опасный участок.", 16, Color("#bce4f1"), true))
    box.add_child(_make_button("ПОНЯТНО — ПОЕХАЛИ", _dismiss_tutorial.bind(overlay, panel), true))


func _dismiss_tutorial(overlay: Control, panel: Control) -> void:
    mode = "running"
    overlay.queue_free()
    panel.queue_free()


func _pause_run() -> void:
    if mode != "running":
        return
    mode = "paused"
    _clear_ui()
    var overlay := ColorRect.new()
    overlay.color = Color(0.005, 0.015, 0.04, 0.72)
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(overlay)
    var panel := _make_panel(ui_root, 0.31, 0.70)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(box)
    box.add_child(_make_label("ПАУЗА", 34, Color("#ffffff"), true))
    box.add_child(_make_label("Забег поставлен на паузу", 15, Color("#9fc7da"), true))
    box.add_child(_make_button("ПРОДОЛЖИТЬ", _resume_run, true))
    box.add_child(_make_button("НАЧАТЬ ЗАНОВО", _restart_run))
    box.add_child(_make_button("В ГЛАВНОЕ МЕНЮ", _quit_to_menu))


func _resume_run() -> void:
    mode = "running"
    _show_hud()


func _reset_track() -> void:
    _clear_dynamic_world()
    for segment in segments:
        if is_instance_valid(segment):
            segment.queue_free()
    segments.clear()
    for index in range(MAX_SEGMENTS):
        segments.append(_create_segment(-11.0 - float(index) * SEGMENT_LENGTH, index == 0))


func _restart_run() -> void:
    _start_run()


func _quit_to_menu() -> void:
    mode = "menu"
    _show_menu()


func _show_results(earned: int) -> void:
    _clear_ui()
    var shade := ColorRect.new()
    shade.color = Color(0.005, 0.015, 0.04, 0.80)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_root.add_child(shade)
    var panel := _make_panel(ui_root, 0.17, 0.86)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 8)
    panel.add_child(box)
    box.add_child(_make_label("ЗАБЕГ ЗАВЕРШЁН", 30, Color("#ffffff"), true))
    box.add_child(_make_label(run_result_reason, 14, Color("#ff9a65"), true))
    _make_gap(box, 4.0)
    box.add_child(_make_label("" + _format_number(last_run_distance) + " МЕТРОВ", 27, Color("#5deaff"), true))
    box.add_child(_make_label("СЧЁТ  " + _format_number(last_run_score), 20, Color("#ffffff"), true))
    box.add_child(_make_label("МОНЕТЫ  " + str(last_run_coins) + "    •    ЗАРАБОТАНО  +" + str(earned), 17, Color("#ffd37a"), true))
    box.add_child(_make_label("ЛУЧШИЙ РЕЗУЛЬТАТ  " + _format_number(int(profile["best_distance"])) + " м", 14, Color("#a8c8d7"), true))
    if not new_mission_rewards.is_empty():
        _make_gap(box, 2.0)
        box.add_child(_make_label("НОВЫЕ НАГРАДЫ", 16, Color("#5ff0c5"), true))
        for reward in new_mission_rewards:
            box.add_child(_make_label(reward, 13, Color("#bcecdf"), true))
    _make_gap(box, 8.0)
    box.add_child(_make_button("ЕЩЁ ОДИН ЗАБЕГ", _restart_run, true))
    box.add_child(_make_button("УЛУЧШИТЬ СНАРЯЖЕНИЕ", _show_shop))
    box.add_child(_make_button("ГЛАВНОЕ МЕНЮ", _show_menu))


func _show_shop() -> void:
    mode = "shop"
    _clear_ui()
    _make_background(ui_root, 0.68)
    var panel := _make_panel(ui_root, 0.09, 0.92)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 10)
    panel.add_child(box)
    box.add_child(_make_label("МАСТЕРСКАЯ", 30, Color("#ffffff"), true))
    shop_balance_label = _make_label("БАЛАНС  " + str(profile["coins"]) + " МОНЕТ", 18, Color("#ffd47a"), true)
    box.add_child(shop_balance_label)
    box.add_child(_make_label("Улучшай снаряжение между забегами", 14, Color("#9dc6d8"), true))
    _make_gap(box, 5.0)
    shop_item_labels.clear()
    for upgrade_id in ["shield", "flux", "magnet"]:
        var data: Dictionary = UPGRADE_DATA[upgrade_id]
        var level: int = int(profile["upgrades"][upgrade_id])
        var row := VBoxContainer.new()
        row.add_theme_constant_override("separation", 3)
        row.add_child(_make_label(str(data["name"]) + "  •  УРОВЕНЬ " + str(level) + "/3", 16, Color("#7cecff")))
        row.add_child(_make_label(str(data["description"]), 13, Color("#afcbd9")))
        var price_text := "МАКСИМАЛЬНЫЙ УРОВЕНЬ"
        if level < data["costs"].size():
            price_text = "УЛУЧШИТЬ  •  " + str(data["costs"][level]) + " МОНЕТ"
        var upgrade_button := _make_button(price_text, _buy_upgrade.bind(upgrade_id), false)
        if level >= data["costs"].size() or int(profile["coins"]) < int(data["costs"][level]):
            upgrade_button.modulate = Color(0.58, 0.68, 0.76, 0.7)
        row.add_child(upgrade_button)
        box.add_child(row)
        shop_item_labels[upgrade_id] = upgrade_button
    _make_gap(box, 5.0)
    box.add_child(_make_button("НАЗАД", _show_menu, true))


func _show_settings() -> void:
    mode = "settings"
    _clear_ui()
    _make_background(ui_root, 0.70)
    var panel := _make_panel(ui_root, 0.22, 0.78)
    var box := VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 13)
    panel.add_child(box)
    box.add_child(_make_label("НАСТРОЙКИ", 30, Color("#ffffff"), true))
    box.add_child(_make_label("ГРОМКОСТЬ ЗВУКА", 16, Color("#8cecff"), true))
    settings_volume = HSlider.new()
    settings_volume.min_value = 0.0
    settings_volume.max_value = 1.0
    settings_volume.step = 0.05
    settings_volume.value = float(profile["volume"])
    settings_volume.custom_minimum_size = Vector2(0.0, 42.0)
    settings_volume.value_changed.connect(_on_volume_changed)
    box.add_child(settings_volume)
    box.add_child(_make_label("Управление: свайпы по экрану", 15, Color("#bad2df"), true))
    box.add_child(_make_label("Сохранения хранятся только на устройстве", 13, Color("#7e9daf"), true))
    box.add_child(_make_button("НАЗАД", _show_menu, true))


func _on_volume_changed(value: float) -> void:
    profile["volume"] = value
    _update_audio_volume()
    _save_profile()


func _clear_dynamic_world() -> void:
    obstacles.clear()
    pickups.clear()


func _format_number(value: int) -> String:
    var raw := str(maxi(0, value))
    var result := ""
    for index in range(raw.length()):
        if index > 0 and (raw.length() - index) % 3 == 0:
            result += " "
        result += raw.substr(index, 1)
    return result


# -----------------------------------------------------------------------------
# Mesh/material helpers
# -----------------------------------------------------------------------------

func _material(color: Color, metallic: float = 0.0, roughness: float = 0.4, emissive: bool = false, glow: float = 1.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metallic
    material.roughness = roughness
    if emissive:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = glow
    return material


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = position
    instance.material_override = material
    parent.add_child(instance)
    return instance


func _add_capsule(parent: Node3D, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = position
    instance.material_override = material
    parent.add_child(instance)
    return instance


func _add_sphere(parent: Node3D, radius: float, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.position = position
    instance.material_override = material
    parent.add_child(instance)
    return instance
