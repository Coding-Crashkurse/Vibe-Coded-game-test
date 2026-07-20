extends SceneTree
## THROWAWAY experiment tool (retarget spike): prints the node tree of the
## imported scenes so the _subresources "PATH:<nodepath>" key for the
## per-Skeleton3D retarget options can be written correctly.

func _walk(n: Node, root: Node, depth: int) -> void:
	var p := String(root.get_path_to(n)) if n != root else "."
	print("%s%s [%s]   PATH:%s" % ["  ".repeat(depth), n.name, n.get_class(), p])
	for c in n.get_children():
		_walk(c, root, depth + 1)


func _dump(path: String) -> void:
	print("\n===== %s" % path)
	var ps: PackedScene = load(path)
	if ps == null:
		print("  LOAD FAILED")
		return
	var root := ps.instantiate()
	_walk(root, root, 0)
	root.free()


func _init() -> void:
	_dump("res://assets/models/anim/rt_swat.glb")
	_dump("res://assets/models/anim/ual.gltf")
	quit()
