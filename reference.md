# Blender + Godot 4 Low-Poly — Reference

## 1. Blender headless invocation

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" \
  --background --factory-startup --python tools/blender_assets.py
```

`--factory-startup` guarantees a clean state regardless of the user's Blender
preferences (units, theme, add-ons).

> **Gotcha:** if the build script calls `read_factory_settings()` it destroys
> cameras and lights created earlier. Order must be *model first, scene setup
> second*, otherwise you get
> `ReferenceError: StructRNA of type Object has been removed`.

## 2. Mesh helpers

```python
def ring_pts(cy, cz, rx, rz, sides, flat_bottom=0.0):
    """One cross-section ring, optionally flattened on the underside."""
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
    """Connect consecutive rings into quads. Rings must share point count."""
    n = len(rings[0])
    verts, faces = [], []
    for r in rings:
        verts.extend(r)
    for k in range(len(rings) - 1):
        a = k * n
        b = (k + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append([a + i, a + j, b + j, b + i])
    if cap_start:
        faces.append(list(range(n - 1, -1, -1)))
    if cap_end:
        base = (len(rings) - 1) * n
        faces.append([base + i for i in range(n)])
    return verts, faces
```

`loft()` treats every ring as a **closed loop**, so a flat profile works too —
tracing left edge → top surface → right edge → back along the bottom yields a
solid slab rather than a paper-thin plane.

### Worked body profile

```python
BODY_PROFILE = [
    # (y, cz, rx, rz, flat_bottom)
    (-0.58, 0.02, 0.014, 0.030, 0.00),   # tail tip
    (-0.36, 0.02, 0.090, 0.078, 0.00),
    (-0.24, 0.04, 0.140, 0.130, 0.12),   # belly starts widening
    ( 0.04, 0.06, 0.200, 0.205, 0.20),   # widest
    ( 0.33, 0.18, 0.098, 0.110, 0.00),   # neck
    ( 0.48, 0.62, 0.090, 0.084, 0.00),   # head
]
rings = [ring_pts(y, cz, rx, rz, SIDES, flat_bottom=fb)
         for (y, cz, rx, rz, fb) in BODY_PROFILE]
```

Deliberately adjusting radius *and* centre height per ring is what separates a
sculpted silhouette from a stretched sphere. `flat_bottom` sinks the belly so it
rests on a saddle.

## 3. Tubes

Build the geometry along **local +Y from 0 to length**, then rotate so +Y aligns
with the target axis. Applying the position *and* the rotation to world-space
vertices double-transforms and silently disconnects every tube.

```python
def tube(name, a, b, r0, r1, material, parent, sides=6, origin=None):
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length            # mathutils Vector.length is a PROPERTY, no ()
    seg = d.normalized()
    rings = []
    for t in (0.0, 1.0):
        c = seg * (length * t)
        r = r0 + (r1 - r0) * t
        rings.append([c + perpendicular * r for perpendicular in _frame(seg)])
    v, f = loft(rings)
    # ... build mesh, then orient +Y → seg
```

> `mathutils.Vector.length` is a **property**. `d.length()` raises
> `TypeError: 'float' object is not callable`.

## 4. Wheel radius

The tyre's outer radius must equal the value used as the axle height:

```python
rr = (WHEEL_R - WHEEL_T) + math.cos(b) * WHEEL_T   # outer == WHEEL_R ✔
# rr = WHEEL_R + math.cos(b) * WHEEL_T             # outer == WHEEL_R + WHEEL_T ✘
```

With the wrong sign the wheel sinks into the ground by exactly `WHEEL_T`.

A polygonal wheel's lowest point is an *edge midpoint*, not a vertex. Shift the
phase by `-pi/2` so a vertex sits at the bottom, and raise the segment count
(20 is plenty) to keep the float jitter under 4 mm while spinning.

## 5. Runtime material conversion

```gdscript
class_name Toon
extends RefCounted

const SHADER_PATH := "res://assets/shaders/toon3color.gdshader"
const OUTLINE_SHADER_PATH := "res://assets/shaders/outline.gdshader"

const SHADOW_TINT := Color(0.74, 0.72, 0.80)
const SHADOW_MUL := 0.50      # 0.76 = soft, 0.50 = deep graphic shadows
const LIGHT_MUL := 1.02

static var outline_px: float = 1.5     # screen pixels, NOT metres


static func apply(root: Node, with_outline: bool = true) -> int:
    var shader: Shader = load(SHADER_PATH)
    var count := 0
    for node in _all_nodes(root):
        if node is MeshInstance3D and node.mesh != null:
            var mesh: Mesh = node.mesh
            for i in mesh.get_surface_count():
                var base := _base_color_of(node, i)
                node.set_surface_override_material(i,
                    make_material(shader, base, 0.30, with_outline))
            count += 1
    return count


static func make_material(shader: Shader, base: Color, rim: float = 0.30,
        with_outline: bool = true) -> ShaderMaterial:
    var m := ShaderMaterial.new()
    m.shader = shader
    m.set_shader_parameter("color_shadow",
        Color(base.r * SHADOW_MUL * SHADOW_TINT.r,
              base.g * SHADOW_MUL * SHADOW_TINT.g,
              base.b * SHADOW_MUL * SHADOW_TINT.b, 1.0))
    m.set_shader_parameter("color_mid", base)
    m.set_shader_parameter("color_light",
        Color(minf(base.r * LIGHT_MUL + 0.06, 1.0),
              minf(base.g * LIGHT_MUL + 0.06, 1.0),
              minf(base.b * LIGHT_MUL + 0.06, 1.0), 1.0))
    m.set_shader_parameter("rim_strength", rim)
    if with_outline and outline_px > 0.0:
        m.next_pass = _make_outline_material()
    return m
```

`_base_color_of()` must fall back through `StandardMaterial3D` → `ShaderMaterial`
→ `BaseMaterial3D` → neutral grey; imported glTF materials are not always the
class you expect.

## 6. Outline maths

```
px = L * (viewport_height / 2) / (depth * tan(fov / 2))
⇒ L = px * depth * tan(fov / 2) * 2 / viewport_height
```

`depth` is `-view_pos.z` in view space. Pass `viewport_height` and `fov_deg` as
uniforms and refresh them from GDScript so window resizes and FOV changes stay
correct.

Fade the outline out between 70 m and 150 m — distant geometry should lose its
contour, which is what atmospheric perspective looks like.

## 7. Endless-runner collision

```gdscript
func _hitbox_of(root: Node3D) -> AABB:
    var area := root.get_node_or_null("HitBox") as Area3D
    if area != null:
        for child in area.get_children():
            if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
                var cs := child as CollisionShape3D
                var size: Vector3 = (cs.shape as BoxShape3D).size
                var center := (area.global_transform * cs.transform).origin
                return AABB(center - size * 0.5, size)
    return _approx_aabb(root)     # fall back to merging the whole subtree
```

`_approx_aabb` **must recurse**. Obstacle scenes are
`root → Model(glb instance) → MeshInstance3D`; scanning only direct children
returns empty boxes and collision silently never fires.

## 8. Difficulty curve

Design in time, convert to distance:

```gdscript
func gap_for_speed(speed: float) -> float:
    var v := clampf(speed, base_speed, max_speed)   # clamp ONCE, use everywhere
    var t := inverse_lerp(base_speed, max_speed, v)
    var interval := lerpf(gap_time_start, gap_time_end, t)
    return maxf(v * interval, min_gap)
```

Two invariants to assert in tests:

1. reaction time (`gap / speed`) decreases monotonically with speed;
2. gap always exceeds one full jump's travel distance (`speed * 2 * v0 / g`).

Clamping only inside `inverse_lerp` while multiplying by the raw speed produces
absurd values (260 m/s → 221 m gap).

## 9. Sky and lighting

Golden hour is made by **deepening shadows**, not brightening lights.

| Setting | Value |
|---|---|
| Tonemap | ACES, exposure ~0.98 |
| Key light | `Color(1, 0.82, 0.58)`, energy ~1.0 |
| Fill light | `Color(0.58, 0.70, 1.0)`, energy ~0.30 (cool, for warm/cool contrast) |
| Ambient | `Color(0.38, 0.40, 0.56)`, energy ~0.26 |
| Sky | blue-violet top → orange horizon, `sky_curve ≈ 0.22` |
| Glow | intensity ~0.10 (soft bloom only) |

> `sun_angle_max` in `ProceduralSkyMaterial` renders as a dark smudge at any size.
> Set it to `0` and fake the sun with a warm key light.
>
> `fog_sky_affect` defaults to `1.0` and floods the entire skybox with the fog
> colour — set it to `0`.
>
> `sky_curve` controls how far the **horizon colour creeps upward**. Larger
> values spread the horizon colour further up; `0.86` paints the whole sky orange.

A pure gradient sky always melts into the ground. **Put a silhouette on the
horizon** — a distant mountain range is the single highest-impact fix.

## 10. Project settings

```ini
[rendering]
renderer/rendering_method="forward_plus"
anti_aliasing/quality/msaa_3d=3            ; 8x — hard low-poly edges need it
anti_aliasing/quality/use_debanding=true   ; kills gradient banding in the sky
anti_aliasing/quality/use_fxaa=false       ; only blurs when MSAA suffices
scaling_3d/scale=1.0
```

Shadow quality: keep `directional_shadow_max_distance` tight (~40 m) or every
texel gets large and shadows turn grainy.

## 11. Tooling traps

- **`.bat` files must be pure ASCII.** `cmd.exe` reads them in the system code
  page (CP950 on zh-TW); UTF-8 Chinese gets shredded into phantom commands.
- **`exit` immediately after `start`** tears down the console before the child
  detaches. Run the executable directly instead, or `ping -n 3 127.0.0.1 >nul`
  first.
- **PowerShell `Set-Content -Encoding UTF8`** writes a BOM in Windows PowerShell
  5.1 and can mangle CJK inside config files. Use the editor/write tool for
  files containing multi-byte text.
- **`String.replace()` in JavaScript replaces only the first match.** Renaming a
  node in a `.tscn` needs `split().join()` or every child keeps the old parent
  path and resolves to `null`.
