# Blender + Godot 4 Low-Poly — 技術參考

> English version: [reference.md](reference.md)

## 1. Blender headless 執行

```bash
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" \
  --background --factory-startup --python tools/blender_assets.py
```

`--factory-startup` 保證每次都從乾淨的預設狀態開始，不受使用者的 Blender
偏好（單位、主題、外掛）影響。

> **陷阱**：如果建構腳本呼叫了 `read_factory_settings()`，它會摧毀先前建立的
> 相機與燈光。順序必須是「先建模、再設定場景」，否則會出現
> `ReferenceError: StructRNA of type Object has been removed`。

## 2. 網格輔助函式

```python
def ring_pts(cy, cz, rx, rz, sides, flat_bottom=0.0):
    """一圈斷面，可選擇壓平底部。"""
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
    """把相鄰兩環連成四邊面。每環點數必須相同。"""
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

`loft()` 把每一環視為**封閉迴圈**，所以平的輪廓也能用 ——
依序走「左緣 → 上表面 → 右緣 → 沿底部回來」，放樣出來就是一塊實心板，
而不是一張紙。

### 實際的斷面表

```python
BODY_PROFILE = [
    # (y, cz, rx, rz, flat_bottom)
    (-0.58, 0.02, 0.014, 0.030, 0.00),   # 尾羽尖端
    (-0.36, 0.02, 0.090, 0.078, 0.00),
    (-0.24, 0.04, 0.140, 0.130, 0.12),   # 腹部開始變寬
    ( 0.04, 0.06, 0.200, 0.205, 0.20),   # 身體最寬處
    ( 0.33, 0.18, 0.098, 0.110, 0.00),   # 頸
    ( 0.48, 0.62, 0.090, 0.084, 0.00),   # 頭
]
rings = [ring_pts(y, cz, rx, rz, SIDES, flat_bottom=fb)
         for (y, cz, rx, rz, fb) in BODY_PROFILE]
```

刻意調整每一環的半徑**與**中心高度，才是「雕塑出的輪廓」與「拉長的球體」
之間的差別。`flat_bottom` 把腹部壓平，讓它貼在座墊上。

## 3. 管子

幾何一律沿著**本地 +Y 從 0 到 length** 建構，再用旋轉把 +Y 對到目標軸。
如果同時把位置套到世界座標「又」旋轉一次，會變成雙重轉換，
每一根管子都會默默斷開。

```python
def tube(name, a, b, r0, r1, material, parent, sides=6, origin=None):
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length            # mathutils 的 Vector.length 是「屬性」，不能加 ()
    seg = d.normalized()
    rings = []
    for t in (0.0, 1.0):
        c = seg * (length * t)
        r = r0 + (r1 - r0) * t
        rings.append([c + perp * r for perp in _frame(seg)])
    v, f = loft(rings)
    # ... 建立 mesh，然後把 +Y 對到 seg
```

> `mathutils.Vector.length` 是**屬性**。寫 `d.length()` 會得到
> `TypeError: 'float' object is not callable`。

## 4. 輪子半徑

輪胎的外徑必須等於軸心高度所用的那個值：

```python
rr = (WHEEL_R - WHEEL_T) + math.cos(b) * WHEEL_T   # 外徑 == WHEEL_R ✔
# rr = WHEEL_R + math.cos(b) * WHEEL_T             # 外徑 == WHEEL_R + WHEEL_T ✘
```

符號寫反的話，輪子會陷進地面，深度剛好是 `WHEEL_T`。

多邊形輪子的最低點是**邊的中點**，不是頂點。把相位偏移 `-pi/2` 讓一個頂點
落在正下方，並把段數提高（20 就很夠），轉動時的浮動可以壓到 4 mm 以下。

## 5. 執行期材質轉換

```gdscript
class_name Toon
extends RefCounted

const SHADER_PATH := "res://assets/shaders/toon3color.gdshader"
const OUTLINE_SHADER_PATH := "res://assets/shaders/outline.gdshader"

const SHADOW_TINT := Color(0.74, 0.72, 0.80)
const SHADOW_MUL := 0.50      # 0.76 = 柔和，0.50 = 深色塊面
const LIGHT_MUL := 1.02

static var outline_px: float = 1.5     # 螢幕像素，不是公尺


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

`_base_color_of()` 必須依序 fallback：`StandardMaterial3D` → `ShaderMaterial`
→ `BaseMaterial3D` → 中性灰。匯入的 glTF 材質不一定是你預期的類別。

## 6. 描邊的數學

```
px = L * (viewport_height / 2) / (depth * tan(fov / 2))
⇒ L = px * depth * tan(fov / 2) * 2 / viewport_height
```

`depth` 是視空間的 `-view_pos.z`。把 `viewport_height` 與 `fov_deg` 當成
uniform 傳進去，並從 GDScript 更新，這樣視窗縮放與 FOV 變化才會正確。

描邊在 70 公尺到 150 公尺之間淡出 —— 遠處的幾何本來就該失去輪廓，
那才是大氣透視該有的樣子。

## 7. 無限跑酷的碰撞

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
    return _approx_aabb(root)     # 退回「合併整個子樹」
```

`_approx_aabb` **必須遞迴**。障礙物場景的結構是
`root → Model(glb 實例) → MeshInstance3D`；只掃直接子節點會回傳空盒子，
碰撞就默默永遠不成立。

## 8. 難度曲線

用時間設計，再換算成距離：

```gdscript
func gap_for_speed(speed: float) -> float:
    var v := clampf(speed, base_speed, max_speed)   # 夾制一次，全程用同一個值
    var t := inverse_lerp(base_speed, max_speed, v)
    var interval := lerpf(gap_time_start, gap_time_end, t)
    return maxf(v * interval, min_gap)
```

測試裡要斷言兩條不變式：

1. 反應時間（`gap / speed`）隨速度單調遞減；
2. 間距永遠大於一次完整跳躍的前進距離（`speed * 2 * v0 / g`）。

只在 `inverse_lerp` 裡夾制、乘的時候仍用原始速度，會算出荒謬的數值
（260 m/s → 221 公尺的間距）。

## 9. 天空與光照

黃金時刻是靠**壓深陰影**做出來的，不是把光調亮。

| 項目 | 值 |
| --- | --- |
| Tonemap | ACES，曝光約 0.98 |
| 主光 | `Color(1, 0.82, 0.58)`，能量約 1.0 |
| 補光 | `Color(0.58, 0.70, 1.0)`，能量約 0.30（冷色，拉出暖冷對比） |
| 環境光 | `Color(0.38, 0.40, 0.56)`，能量約 0.26 |
| 天空 | 頂端藍紫 → 地平線橘金，`sky_curve ≈ 0.22` |
| Glow | 強度約 0.10（只做柔光） |

> `ProceduralSkyMaterial` 的 `sun_angle_max` 不管設多大都會渲染成一塊深色
> 污漬。設成 `0`，用暖色主光去假裝太陽。
>
> `fog_sky_affect` 預設是 `1.0`，會把整個天空盒染成單一霧色 —— 設成 `0`。
>
> `sky_curve` 控制的是**地平線色往上蔓延的範圍**。值越大橘色擴散越廣；
> `0.86` 會把整個天空畫成橘色。

純漸層的天空永遠會跟地面糊在一起。**在地平線上放一個實體剪影** ——
遠處的山脈是效果最大的一個修正。

## 10. 專案設定

```ini
[rendering]
renderer/rendering_method="forward_plus"
anti_aliasing/quality/msaa_3d=3            ; 8x —— Low-Poly 的硬邊需要
anti_aliasing/quality/use_debanding=true   ; 消除天空漸層的色帶
anti_aliasing/quality/use_fxaa=false       ; MSAA 足夠時只會讓畫面變糊
scaling_3d/scale=1.0
```

陰影品質：`directional_shadow_max_distance` 要收緊（約 40 公尺），
否則每個 texel 都很大，陰影會出現顆粒。

## 11. 工具鏈的坑

- **`.bat` 檔只能用純 ASCII。** `cmd.exe` 用系統碼頁（繁中 Windows 是 CP950）
  讀批次檔，UTF-8 中文會被拆成碎片變成不存在的指令。
- **`start` 之後立刻 `exit`** 會在子程序完成脫離前把 console 拆掉。
  直接執行 exe，或先 `ping -n 3 127.0.0.1 >nul` 撐一下。
- **PowerShell 的 `Set-Content -Encoding UTF8`** 在 Windows PowerShell 5.1 會
  寫入 BOM，而且可能弄壞設定檔裡的中文。含多位元組文字檔案請用編輯器或
  write 工具處理。
- **JavaScript 的 `String.replace()` 只換第一個匹配。** 在 `.tscn` 裡改節點名稱
  要用 `split().join()`，否則子節點會保留舊的 parent 路徑並解析成 `null`。
