extends CharacterBody3D
class_name Explorer

signal selection_changed(id: int)

var world: VoxelWorld
var camera: Camera3D
var selected := 1
var sensitivity := 0.0025
var can_move := false
var menu_open := false
var touch_enabled := false
var move_touch := -1
var look_touch := -1
var move_origin := Vector2.ZERO
var touch_move := Vector2.ZERO
var jump_queued := false
var outline: MeshInstance3D

func _ready() -> void:
 var collider := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.3
 capsule.height = 1.8
 collider.shape = capsule
 collider.position.y = 0.9
 add_child(collider)
 camera = Camera3D.new()
 camera.position.y = 1.62
 camera.fov = 75
 camera.far = 120
 add_child(camera)
 camera.current = true
 _make_outline()

func _make_outline() -> void:
 var immediate := ImmediateMesh.new()
 immediate.surface_begin(Mesh.PRIMITIVE_LINES)
 var a := [Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1)]
 for edge in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
  immediate.surface_add_vertex(a[edge[0]] * 1.006 - Vector3.ONE * 0.003)
  immediate.surface_add_vertex(a[edge[1]] * 1.006 - Vector3.ONE * 0.003)
 immediate.surface_end()
 var mat := StandardMaterial3D.new()
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.albedo_color = Color(0.08,0.10,0.08,0.8)
 immediate.surface_set_material(0,mat)
 outline = MeshInstance3D.new()
 outline.mesh = immediate
 outline.visible = false
 get_parent().call_deferred("add_child", outline)

func _physics_process(delta: float) -> void:
 if not can_move or menu_open:
  velocity = Vector3.ZERO
  return
 var axis := Vector2.ZERO
 axis.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
 axis.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
 if touch_move.length() > 0.05:
  axis = touch_move
 axis = axis.limit_length(1.0)
 var direction := (transform.basis * Vector3(axis.x,0,axis.y)).normalized() * axis.length()
 var speed := 8.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 5.5
 velocity.x = direction.x * speed
 velocity.z = direction.z * speed
 if not is_on_floor():
  velocity.y -= 24.0 * delta
 elif Input.is_physical_key_pressed(KEY_SPACE) or jump_queued:
  velocity.y = 8.0
 jump_queued = false
 move_and_slide()
 if position.y < -20:
  respawn()
 var hit := _raycast()
 outline.visible = not hit.is_empty()
 if not hit.is_empty():
  outline.global_position = Vector3(_hit_block(hit, false))

func respawn() -> void:
 position = Vector3(0.5, float(world.heights.get(Vector2i(0,0), 15)) + 2.0, 0.5)
 velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
 if not can_move or menu_open:
  return
 if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
  _look(event.relative)
 elif event is InputEventMouseButton and event.pressed:
  if event.button_index == MOUSE_BUTTON_LEFT:
   interact(false)
  elif event.button_index == MOUSE_BUTTON_RIGHT:
   interact(true)
  elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
   select_block(posmod(selected - 2, 7) + 1)
  elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
   select_block(posmod(selected, 7) + 1)
 elif event is InputEventKey and event.pressed and not event.echo:
  if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_7:
   select_block(event.physical_keycode - KEY_1 + 1)
 elif touch_enabled and event is InputEventScreenTouch:
  if event.pressed:
   if event.position.x < get_viewport().get_visible_rect().size.x * 0.45 and move_touch == -1:
    move_touch = event.index
    move_origin = event.position
   elif look_touch == -1:
    look_touch = event.index
  else:
   if event.index == move_touch:
    move_touch = -1
    touch_move = Vector2.ZERO
   if event.index == look_touch:
    look_touch = -1
 elif touch_enabled and event is InputEventScreenDrag:
  if event.index == move_touch:
   touch_move = ((event.position - move_origin) / 65.0).limit_length(1.0)
  elif event.index == look_touch:
   _look(event.relative * 1.4)

func _look(relative: Vector2) -> void:
 rotate_y(-relative.x * sensitivity)
 camera.rotation.x = clampf(camera.rotation.x - relative.y * sensitivity, -1.5, 1.5)

func select_block(id: int) -> void:
 selected = clampi(id,1,7)
 selection_changed.emit(selected)

func _raycast() -> Dictionary:
 var from := camera.global_position
 var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_transform.basis.z * 6.0)
 query.exclude = [get_rid()]
 return get_world_3d().direct_space_state.intersect_ray(query)

func _hit_block(hit: Dictionary, placing: bool) -> Vector3i:
 var p: Vector3 = hit.position + hit.normal * (0.01 if placing else -0.01)
 return Vector3i(floori(p.x), floori(p.y), floori(p.z))

func interact(placing: bool) -> void:
 if not can_move or menu_open:
  return
 var hit := _raycast()
 if hit.is_empty():
  return
 var p := _hit_block(hit, placing)
 if placing:
  # Never place a solid block inside the explorer.
  var player_box := AABB(global_position + Vector3(-0.3,0,-0.3), Vector3(0.6,1.8,0.6))
  if player_box.intersects(AABB(Vector3(p), Vector3.ONE)) or world.get_block(p) != 0:
   return
  world.edit_block(p, selected)
 else:
  world.edit_block(p, 0)
