class_name TerrainUtils
extends RefCounted

# FIX: Negative Coordinate Noise Glitch
# Godot dùng int 64-bit có dấu. Phép >> gây sign-extension với số âm,
# làm kết quả hash sai hoàn toàn ở tọa độ âm (x<0 hoặc z<0).
# Giải pháp: áp dụng (& 0xffffffff) sau mỗi bước để ép về uint32.
static func hash_u32(value: int) -> int:
	value = (value ^ (value >> 16)) & 0xffffffff
	value = (value * 0x7feb352d)    & 0xffffffff
	value = (value ^ (value >> 15)) & 0xffffffff
	value = (value * 0x846ca68b)    & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return value


static func random_01(x: int, z: int, salt: int, generation_seed: int) -> float:
	var value := hash_u32(x * 73856093 ^ z * 19349663 ^ generation_seed ^ salt)
	return float(value & 0x00ffffff) / 16777215.0


static func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0


static func chunk_coord_for_cell(cell_x: int, cell_z: int, chunk_size: int) -> Vector2i:
	return Vector2i(
		floori(float(cell_x) / float(chunk_size)),
		floori(float(cell_z) / float(chunk_size))
	)
