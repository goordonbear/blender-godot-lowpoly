# Blender headless 程序化建模的最小可用骨架
#
# 這三個函式是整套 low-poly 建模法的核心：
#   ring_pts  產生一圈斷面頂點（可壓平底部）
#   loft      把相鄰兩圈連成四邊面 —— 這是「雕塑」而不是「拼積木」的關鍵
#   obj_from  把 verts/faces 變成 Blender 物件
#
# 用法：
#   blender --background --factory-startup --python this_file.py

import math
import bpy
from mathutils import Vector

SIDES = 12          # 斷面邊數。8 在近距離會看到明顯折角，12 剛好


def reset():
    """清空場景。務必在建立相機／燈光「之前」呼叫。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough=0.7):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1.0)
    return m


def ring_pts(cy, cz, rx, rz, sides=SIDES, flat_bottom=0.0):
    """一圈斷面。flat_bottom 會壓平 Z 軸負向那一半（腹部貼座墊之類）。"""
    pts = []
    for i in range(sides):
        a = 2 * math.pi * i / sides
        y = math.cos(a) * rx
        z = math.sin(a) * rz
        if z < 0 and flat_bottom > 0:
            z *= (1.0 - flat_bottom)
        pts.append(Vector((0.0, cy + y, cz + z)))
    return pts


def loft(rings, cap_start=True, cap_end=True):
    """把相鄰兩圈的同序號頂點連成四邊面。每圈點數必須相同。

    回傳 (verts, faces)。rings 被視為「封閉迴圈」——
    所以一條平的打橫輪廓（左緣→路面→右緣→沿底部回來）會放樣成實心板。
    """
    n = len(rings[0])
    verts, faces = [], []
    for r in rings:
        verts.extend(r)
    for k in range(len(rings) - 1):
        a, b = k * n, (k + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append([a + i, a + j, b + j, b + i])
    if cap_start:
        faces.append(list(range(n - 1, -1, -1)))
    if cap_end:
        base = (len(rings) - 1) * n
        faces.append([base + i for i in range(n)])
    return verts, faces


def obj_from(name, verts, faces, materials, parent=None, origin=(0, 0, 0), flat=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [list(f) for f in faces])
    me.validate(verbose=False)
    me.update()
    for m in materials:
        me.materials.append(m)
    if flat:
        for poly in me.polygons:
            poly.use_smooth = False       # 平面著色 = low-poly 的切面感
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.location = origin
    if parent:
        ob.parent = parent
    return ob


# ---------------------------------------------------------------------------
#  範例：一根有弧度的管子（車架、樹枝、腿）
#
#  重點：幾何一律沿「本地 +Y 從 0 到 length」建構，再用旋轉把 +Y 對到目標軸。
#  如果同時把位置套到世界座標「又」旋轉一次，每根管子都會斷開。
# ---------------------------------------------------------------------------
def tube(name, a, b, r0, r1, material, parent=None, sides=6, origin=None):
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length              # mathutils 的 .length 是屬性，不能加 ()
    seg = d.normalized()

    # 建立一組垂直於 seg 的正交基底
    ref = Vector((0, 0, 1)) if abs(seg.z) < 0.9 else Vector((1, 0, 0))
    nx = ref.cross(seg).normalized()
    ny = seg.cross(nx).normalized()

    rings = []
    for t in (0.0, 1.0):
        c = seg * (length * t)
        r = r0 + (r1 - r0) * t
        pts = []
        for i in range(sides):
            ang = 2 * math.pi * i / sides
            pts.append(c + nx * (math.cos(ang) * r) + ny * (math.sin(ang) * r))
        rings.append(pts)

    v, f = loft(rings)
    return obj_from(name, v, f, [material], parent=parent,
                    origin=a if origin is None else origin)


if __name__ == "__main__":
    reset()
    root = bpy.data.objects.new("Root", None)
    bpy.context.collection.objects.link(root)

    body = mat("Body", (0.95, 0.93, 0.88))
    metal = mat("Metal", (0.20, 0.55, 0.62))

    prof = [(0.00, 0.05), (0.30, 0.12), (0.60, 0.09), (0.85, 0.04)]
    rings = [ring_pts(y, 0.0, r, r * 0.9, flat_bottom=0.15) for (y, r) in prof]
    v, f = loft(rings)
    obj_from("DemoBody", v, f, [body], parent=root)

    tube("DemoTube", (0, -0.3, 0), (0, 0.5, 0.3), 0.02, 0.015, metal, parent=root)

    out = "demo.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB",
                              export_yup=True, use_selection=True)
    print("exported", out)
