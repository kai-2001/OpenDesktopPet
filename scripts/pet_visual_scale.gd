class_name PetVisualScale
extends RefCounted

const MIN_VALUE := 0.5
const MAX_VALUE := 1.5
const DEFAULT_VALUE := 1.0
const STEP := 0.05


static func normalize(value: float) -> float:
	return snappedf(clampf(value, MIN_VALUE, MAX_VALUE), STEP)
