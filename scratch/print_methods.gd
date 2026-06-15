extends SceneTree

func _init() -> void:
	print("--- PhysicsServer3D Methods ---")
	var methods = []
	for method in PhysicsServer3D.get_method_list():
		methods.append(method.name)
	methods.sort()
	for name in methods:
		if "flush" in name or "space" in name or "sync" in name:
			print(name)
	quit(0)
