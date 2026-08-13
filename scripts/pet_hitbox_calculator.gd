class_name PetHitboxCalculator
extends RefCounted

const ALPHA_THRESHOLD := 0.08
const POLYGON_EPSILON := 2.0


func content_polygon(image: Image, pixel_rect: Rect2i) -> PackedVector2Array:
	var content_bounds := content_bounds(image, pixel_rect)
	if content_bounds.size == Vector2.ZERO:
		return PackedVector2Array()
	return PackedVector2Array([
		content_bounds.position,
		Vector2(content_bounds.end.x, content_bounds.position.y),
		content_bounds.end,
		Vector2(content_bounds.position.x, content_bounds.end.y),
	])


func content_bounds(image: Image, pixel_rect: Rect2i) -> Rect2:
	if image == null or image.is_empty() or pixel_rect.size.x <= 0 or pixel_rect.size.y <= 0:
		return Rect2()
	var frame_image := image.get_region(pixel_rect)
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(frame_image, ALPHA_THRESHOLD)
	var polygons: Array[PackedVector2Array] = bitmap.opaque_to_polygons(
		Rect2i(Vector2i.ZERO, frame_image.get_size()),
		POLYGON_EPSILON
	)
	var bounds := Rect2()
	var has_point := false
	for polygon: PackedVector2Array in polygons:
		for point: Vector2 in polygon:
			if has_point:
				bounds = bounds.expand(point)
			else:
				bounds = Rect2(point, Vector2.ZERO)
				has_point = true
	return bounds
