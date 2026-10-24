# blender-godot-lowpoly

An Agent Skill for building low-poly 3D games with **Blender headless procedural
modelling** and **Godot 4**.

Distilled from a shipped endless runner: a pelican riding a bicycle along a
coastal road, with procedural meshes, cel shading, cartoon outlines, procedural
audio and a 51-check test suite.

## What it teaches

| Topic | Detail |
| --- | --- |
| Modelling | Cross-section **lofting** — sculpted silhouettes, not assembled primitives |
| Coordinates | Blender `+Y/+Z` → glTF `export_yup` → Godot `-Z/+Y`, and every trap that follows |
| Rigging | Origins on joints so `rotation` needs no pivot correction |
| Materials | Runtime PBR → three-band cel conversion; base colour drives the palette |
| Outlines | Inverted hull with **fixed screen-pixel width**, plus when to disable it |
| Architecture | Endless-runner layering: config resource, state machine, AABB collision |
| Difficulty | Design in reaction time, then convert to distance — never the other way round |
| Verification | Headless test runner + `--write-movie` frame inspection |
| Tooling | `.bat` encoding, BOM traps, JavaScript `replace()` pitfalls |

## Install

Copy the folder into your skills directory:

```bash
# personal (all projects)
cp -r blender-godot-lowpoly ~/.agents/skills/

# project-scoped
cp -r blender-godot-lowpoly <your-repo>/.cursor/skills/
```

Then mention it explicitly, e.g. *"use the blender-godot-lowpoly skill"*.

## Contents

```
SKILL.md                          entry point — workflow, rules, traps
reference.md                      full code: helpers, shaders, constants, formulas
templates/blender_loft.py         runnable mesh helper skeleton
templates/toon3color.gdshader     three-band cel shader
templates/outline.gdshader        inverted-hull outline, pixel-width based
```

The two shaders and the Python helper are **not excerpts** — they are the files
that shipped and were verified in engine.

## Quick taste

```python
# one continuous mesh, ring by ring
rings = [ring_pts(y, cz, rx, rz, SIDES, flat_bottom=fb)
         for (y, cz, rx, rz, fb) in BODY_PROFILE]
verts, faces = loft(rings)
```

```glsl
// outline width in pixels, not metres
float world_w = outline_px * depth * tan(radians(fov_deg) * 0.5) * 2.0 / viewport_height;
VERTEX += dir * world_w * fade;
```

## License

MIT — see [LICENSE](LICENSE).