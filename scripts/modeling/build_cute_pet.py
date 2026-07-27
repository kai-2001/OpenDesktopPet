import bpy
import math
import os
from mathutils import Vector


PROJECT_DIR = r"C:\Apache24\htdocs\SealBall_DesktopPet"
OUTPUT_DIR = os.path.join(PROJECT_DIR, "private_pets", "active", "model")
BLEND_PATH = os.path.join(OUTPUT_DIR, "cute_seal_pet.blend")
GLB_PATH = os.path.join(OUTPUT_DIR, "cute_seal_pet.glb")
PREVIEW_PATH = os.path.join(OUTPUT_DIR, "cute_seal_pet_preview.png")


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        pass


def material(name, color, roughness=0.82):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.22
    return mat


def uv_part(name, location, scale, mat, segments=64, rings=32, rotation=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def cone_part(name, location, radius, depth, mat, rotation=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cone_add(
        vertices=32,
        radius1=radius,
        radius2=0.025,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def curve_part(name, points, bevel, mat, parent=None):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = bevel
    curve.bevel_resolution = 5
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bp, point in zip(spline.bezier_points, points):
        bp.co = point
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    curve.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def empty(name, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.25
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


def set_expression(objects, expression_name, visible):
    for obj in objects:
        obj["expression"] = expression_name
        obj.hide_render = not visible
        obj.hide_viewport = not visible


def build_model():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    clear_scene()

    blue = material("MAT_Body_PastelBlue", (0.43, 0.60, 0.78))
    cream = material("MAT_Belly_And_Flippers", (0.96, 0.89, 0.72))
    white = material("MAT_Spots_And_Teeth", (0.97, 0.98, 0.95))
    ink = material("MAT_Ink_BlueGray", (0.08, 0.14, 0.22))
    salmon = material("MAT_Mouth_Salmon", (0.92, 0.48, 0.42))
    tongue = material("MAT_Tongue", (0.98, 0.61, 0.62))

    root = empty("PetRoot")
    root["design_note"] = "Exactly two cream front flippers and one blue forked rear tail."
    root["expression_default"] = "neutral"

    body = uv_part("Body", (0, 0, 0), (1.72, 1.48, 1.68), blue, parent=root)
    belly = uv_part("BellyPatch", (0, -1.37, -0.18), (1.34, 0.18, 1.29), cream, parent=root)
    muzzle = uv_part("Muzzle", (0, -1.52, 0.54), (0.78, 0.18, 0.38), blue, parent=root)

    ear_l = uv_part("Ear_L", (-1.17, -0.31, 1.31), (0.34, 0.25, 0.33), blue, parent=root)
    ear_r = uv_part("Ear_R", (1.17, -0.31, 1.31), (0.34, 0.25, 0.33), blue, parent=root)
    flipper_l_ctrl = empty("FrontFlipper_L_CTRL", (-1.35, -0.82, -0.93))
    flipper_r_ctrl = empty("FrontFlipper_R_CTRL", (1.35, -0.82, -0.93))
    flipper_l_ctrl.parent = root
    flipper_r_ctrl.parent = root
    flipper_l_ctrl["limb_role"] = "front_flipper"
    flipper_r_ctrl["limb_role"] = "front_flipper"
    uv_part(
        "FrontFlipper_L",
        (0, 0, 0),
        (0.62, 0.27, 0.31),
        cream,
        rotation=(0.08, -0.30, -0.35),
        parent=flipper_l_ctrl,
    )
    uv_part(
        "FrontFlipper_R",
        (0, 0, 0),
        (0.62, 0.27, 0.31),
        cream,
        rotation=(-0.08, 0.30, 0.35),
        parent=flipper_r_ctrl,
    )

    tail_ctrl = empty("RearTail_CTRL", (0, 1.35, -0.86))
    tail_ctrl.parent = root
    tail_ctrl["limb_role"] = "single_forked_rear_tail"
    uv_part(
        "RearTail_Lobe_L",
        (-0.38, 0.34, 0),
        (0.70, 0.28, 0.30),
        blue,
        rotation=(0.0, 0.42, -0.34),
        parent=tail_ctrl,
    )
    uv_part(
        "RearTail_Lobe_R",
        (0.38, 0.34, 0),
        (0.70, 0.28, 0.30),
        blue,
        rotation=(0.0, -0.42, 0.34),
        parent=tail_ctrl,
    )
    uv_part("RearTail_Base", (0, 0.14, 0), (0.48, 0.34, 0.32), blue, parent=tail_ctrl)

    for name, loc, scale in (
        ("Spot_R_Upper", (1.69, -0.18, 0.48), (0.035, 0.18, 0.25)),
        ("Spot_R_Middle", (1.74, -0.17, -0.05), (0.032, 0.14, 0.19)),
        ("Spot_R_Lower", (1.68, -0.05, -0.48), (0.035, 0.20, 0.16)),
        ("Spot_L_Upper", (-1.69, -0.18, 0.48), (0.035, 0.18, 0.25)),
        ("Spot_L_Middle", (-1.74, -0.17, -0.05), (0.032, 0.14, 0.19)),
        ("Spot_L_Lower", (-1.68, -0.05, -0.48), (0.035, 0.20, 0.16)),
    ):
        uv_part(name, loc, scale, white, parent=root)

    face_root = empty("FaceRoot", (0, 0, 0))
    face_root.parent = root

    neutral = [
        curve_part(
            "Eye_Neutral_L",
            [(-0.72, -1.58, 0.88), (-0.55, -1.65, 0.82), (-0.38, -1.58, 0.88)],
            0.045,
            ink,
            face_root,
        ),
        curve_part(
            "Eye_Neutral_R",
            [(0.38, -1.58, 0.88), (0.55, -1.65, 0.82), (0.72, -1.58, 0.88)],
            0.045,
            ink,
            face_root,
        ),
        curve_part(
            "Mouth_Neutral",
            [(-0.18, -1.79, 0.38), (0, -1.84, 0.30), (0.18, -1.79, 0.38)],
            0.04,
            ink,
            face_root,
        ),
    ]
    set_expression(neutral, "neutral", True)

    open_face = [
        uv_part("Eye_Open_L", (-0.55, -1.57, 0.84), (0.14, 0.07, 0.20), ink, parent=face_root),
        uv_part("Eye_Open_R", (0.55, -1.57, 0.84), (0.14, 0.07, 0.20), ink, parent=face_root),
        uv_part("Mouth_Open", (0, -1.76, 0.33), (0.42, 0.09, 0.34), salmon, parent=face_root),
        uv_part("Tongue", (0, -1.84, 0.20), (0.25, 0.055, 0.13), tongue, parent=face_root),
    ]
    set_expression(open_face, "open_mouth", False)

    happy = [
        curve_part(
            "Eye_Happy_L",
            [(-0.73, -1.59, 0.82), (-0.55, -1.67, 0.94), (-0.36, -1.59, 0.82)],
            0.05,
            ink,
            face_root,
        ),
        curve_part(
            "Eye_Happy_R",
            [(0.36, -1.59, 0.82), (0.55, -1.67, 0.94), (0.73, -1.59, 0.82)],
            0.05,
            ink,
            face_root,
        ),
        uv_part("Mouth_Happy", (0, -1.76, 0.34), (0.46, 0.09, 0.36), salmon, parent=face_root),
        uv_part("Tongue_Happy", (0, -1.84, 0.20), (0.28, 0.055, 0.14), tongue, parent=face_root),
    ]
    set_expression(happy, "happy", False)

    cone_part("Fang_L", (-0.30, -1.72, 0.43), 0.08, 0.23, white, rotation=(math.pi, 0, 0), parent=face_root)
    cone_part("Fang_R", (0.30, -1.72, 0.43), 0.08, 0.23, white, rotation=(math.pi, 0, 0), parent=face_root)
    uv_part("Nose", (0, -1.72, 0.63), (0.07, 0.035, 0.045), ink, parent=face_root)

    return root


def add_lighting_and_camera():
    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.045, 0.055, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.32

    bpy.ops.object.light_add(type="AREA", location=(-4.5, -5.5, 6.0))
    key = bpy.context.object
    key.name = "Key_Softbox"
    key.data.energy = 850
    key.data.shape = "DISK"
    key.data.size = 5.0
    key.rotation_euler = (math.radians(26), 0, math.radians(-36))

    bpy.ops.object.light_add(type="AREA", location=(4.0, -1.5, 3.0))
    fill = bpy.context.object
    fill.name = "Fill_Softbox"
    fill.data.energy = 450
    fill.data.size = 4.0
    fill.rotation_euler = (math.radians(62), 0, math.radians(120))

    bpy.ops.object.camera_add(location=(0, -8.8, 1.0))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 5.2
    camera.rotation_euler = (math.radians(82), 0, 0)
    direction = Vector((0, 0, 0.1)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera


def export_files():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.use_freestyle = True
    scene.render.line_thickness = 1.15
    freestyle = bpy.context.view_layer.freestyle_settings
    freestyle.linesets[0].linestyle.color = (0.10, 0.18, 0.28)
    freestyle.linesets[0].linestyle.thickness = 1.25
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = True
    scene.render.filepath = PREVIEW_PATH
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_visible=False,
        export_extras=True,
        export_yup=True,
    )
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    build_model()
    add_lighting_and_camera()
    export_files()
    print("BLEND:", BLEND_PATH)
    print("GLB:", GLB_PATH)
    print("PREVIEW:", PREVIEW_PATH)
