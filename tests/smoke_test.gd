extends SceneTree

# Run with an isolated XDG_DATA_HOME: this test modifies the local saved world.
func _initialize() -> void:
 call_deferred("_run")

func _check(condition: bool, message: String) -> bool:
 if not condition:
  push_error("SMOKE TEST FAILED: " + message)
 return condition

func _run() -> void:
 var game: Variant = load("res://main.tscn").instantiate()
 root.add_child(game)
 var world: VoxelWorld = game.world
 var player: Explorer = game.player
 var frames := 0
 while not world.ready_to_play and frames < 1000:
  await process_frame
  frames += 1
 if not _check(world.ready_to_play, "world generation did not finish"):
  quit(1)
  return
 if not _check(player.can_move and world.chunks.size() == 36, "player or chunks not initialized"):
  quit(1)
  return
 # Allow the character to fall onto the generated terrain.
 for i in range(120):
  await physics_frame
 if not _check(player.is_on_floor(), "player did not land on the terrain"):
  quit(1)
  return
 # Exercise the same physical-key path used by keyboard movement.
 var start_position: Vector3 = player.global_position
 var forward := InputEventKey.new()
 forward.physical_keycode = KEY_W
 forward.pressed = true
 Input.parse_input_event(forward)
 for i in range(20):
  await physics_frame
 forward.pressed = false
 Input.parse_input_event(forward)
 if not _check(player.global_position.distance_to(start_position) > 0.1, "keyboard movement did not move the player"):
  quit(1)
  return
 var h: int = world.heights[Vector2i(0, 0)]
 var surface := Vector3i(0, h, 0)
 var original := world.get_block(surface)
 player.global_position = Vector3(0.5, h + 1.05, 0.5)
 player.velocity = Vector3.ZERO
 player.camera.rotation.x = -PI / 2.0 + 0.01
 await physics_frame
 if not _check(not player._raycast().is_empty(), "look ray did not hit the ground"):
  quit(1)
  return
 player.interact(false)
 if not _check(world.get_block(surface) == 0, "mining did not remove the surface block"):
  quit(1)
  return
 await process_frame
 await physics_frame
 player.select_block(original)
 player.interact(true)
 if not _check(world.get_block(surface) == original, "placing did not restore the surface block"):
  quit(1)
  return
 # Verify the settings UI changes the camera and persists its value.
 var hud: Variant = game.hud
 hud._toggle_settings(true)
 if not _check(player.menu_open and hud.settings.visible, "settings did not pause the player"):
  quit(1)
  return
 var sliders: Array = hud.settings.find_children("*", "HSlider", true, false)
 if not _check(sliders.size() == 3, "graphics controls are missing"):
  quit(1)
  return
 sliders[0].value = 83.0
 if not _check(is_equal_approx(player.camera.fov, 83.0), "field of view setting did not apply"):
  quit(1)
  return
 hud._toggle_settings(false)
 if not _check(not player.menu_open, "player remained paused after closing settings"):
  quit(1)
  return
 var settings_save := ConfigFile.new()
 if not _check(settings_save.load("user://settings.cfg") == OK and is_equal_approx(settings_save.get_value("graphics", "fov", 0.0), 83.0), "settings did not save"):
  quit(1)
  return
 var save := ConfigFile.new()
 if not _check(save.load("user://world.cfg") == OK, "block edits were not saved"):
  quit(1)
  return
 var edits: Dictionary = save.get_value("world", "edits", {})
 if not _check(edits.get(surface, 0) == original, "saved block does not match"):
  quit(1)
  return
 # Let the rebuilt collision mesh enter the physics world before mining again.
 await process_frame
 await physics_frame
 # A removed block should remain removed after restarting the game.
 player.interact(false)
 if not _check(world.get_block(surface) == 0, "second mining action failed"):
  quit(1)
  return
 game.queue_free()
 await process_frame
 var restarted: Variant = load("res://main.tscn").instantiate()
 root.add_child(restarted)
 var reloaded_world: VoxelWorld = restarted.world
 frames = 0
 while not reloaded_world.ready_to_play and frames < 1000:
  await process_frame
  frames += 1
 if not _check(reloaded_world.ready_to_play and reloaded_world.get_block(surface) == 0, "saved edits were not loaded"):
  quit(1)
  return
 if not _check(is_equal_approx(restarted.player.camera.fov, 83.0), "saved settings were not loaded"):
  quit(1)
  return
 print("SMOKE TEST PASSED: generation, movement, collision, raycast, mining, placing, settings and save/load")
 quit(0)
