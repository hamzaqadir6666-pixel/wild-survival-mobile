extends SceneTree
func _init():
	var s := Shader.new()
	s.code = "shader_type spatial;\nvoid fragment(){ ALBEDO = vec3(1.0) * UNKNOWN_THING; }"
	var m := ShaderMaterial.new(); m.shader = s
	print("--- now the real ones")
	for n in ["terrain", "water", "veg", "fur", "sky", "rain"]:
		var sh: Shader = load("res://shaders/%s.gdshader" % n)
		var mm := ShaderMaterial.new(); mm.shader = sh
		print(n, " uniforms: ", sh.get_shader_uniform_list().size())
	quit()
