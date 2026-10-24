---
name: blender-godot-lowpoly
description: Builds low-poly 3D games with Blender headless procedural modelling and Godot 4 — cross-section lofting instead of primitives, joint-pivoted rigs, runtime PBR-to-toon material conversion, inverted-hull outlines with fixed pixel width, and endless-runner architecture. Use when creating or modifying a Blender+Godot pipeline, writing procedural mesh generators, troubleshooting part alignment / coordinate conversion / outline artifacts, or building stylised low-poly games in Godot 4.
---

# Blender + Godot 4 Low-Poly Pipeline

Procedural modelling in Blender → glTF → Godot 4 with a cel-shaded look.
Battle-tested on a shipped endless runner (pelican on a bicycle, coastal scene).

## Core principle

**Blender owns geometry and base colour. Godot owns style.**

Materials are converted at runtime, so changing the art direction never requires
re-exporting a single mesh. Keep the Blender script free of shading decisions.

## Workflow

```
1. Model in Blender headless      →  blender --background --factory-startup --python
2. Export .glb (export_yup=True)  →  assets/models/*.glb
3. Wrap each glb in a .tscn       →  Node3D root + script + glb child
4. Import into Godot              →  --headless --editor --quit   (registers class_name too)
5. Convert materials at runtime   →  Toon.apply(root)
6. Verify by recording frames     →  --write-movie out.avi (headless cannot render)
```

Never skip step 4 after adding a `class_name` — you get
`Identifier "X" not declared in the current scope`.

## Modelling: cross-section lofting

Do **not** assemble primitives. Build one continuous mesh by lofting rings:

```
ring 1 → ring 2 → ring 3 → … → ring N
```

Each ring is a list of `Vector` points; `loft()` connects corresponding vertices
into quads. Shape comes from varying each ring's radius, centre and profile.

Benefits: sculpted silhouettes, clean quad topology, and flat shading naturally
produces the faceted low-poly look.

See `templates/blender_loft.py` for the reusable `loft` / `tube` / `obj_from`
helpers, and `reference.md` for a worked body-profile example.

## Coordinate conversion (the #1 source of misplaced parts)

| | Blender | Godot |
|---|---|---|
| Forward | +Y | **-Z** |
| Up | +Z | **+Y** |
| Right | +X | +X |

Export with `export_yup=True`. A circle in Blender's YZ plane becomes Godot's
ZY (rotation about X).

## Rigging rule: put the origin on the joint

Every animatable part's origin sits on its rotation axis, so Godot can just set
`rotation` with no pivot correction:

```
Rider
├── Bike
│   ├── WheelFront / WheelRear     origin at hub
│   └── Crank                      origin at bottom bracket
└── ThighL → ShinL → FootL         hip / knee / ankle
```

Keep the joint constants duplicated in both scripts and treat them as a contract
(`HIP_Y`, `L_THIGH`, `L_SHIN`, `WHEEL_R`).

## Material conversion

`Toon.apply()` walks every `MeshInstance3D`, reads the imported base colour and
installs a three-band cel material. See `reference.md` for the code and
`templates/toon3color.gdshader`.

Two hard-won rules:

- **Outline width must be in screen pixels, not metres.** A fixed world-space
  width makes the same character a fat black halo up close and invisible at
  distance — that is exactly what "the outline looks unnatural" means.
- **Multi-blob objects need the outline disabled.** Each blob expands its own
  hull; small blobs poke through large ones and you get dark lines *inside*
  the object. Add an `outline` export flag on the wrapper script.

## Godot 4 project skeleton

| Script | Responsibility |
|---|---|
| `GameConfig` (Resource) | every tunable number + difficulty formulas |
| `GameState` (Autoload) | high score persistence |
| `GameManager` | state machine, score, collision, hitstop |
| `World` | scrolling, spawning, backdrop |
| `PlayerController` | animation (IK), jump, squash |
| `CameraRig` | follow, FOV, shake |
| `HUD` | panels, modals |
| `Sfx` | procedural audio |

## Endless-runner decisions that matter

- **Player stays at the origin; the world scrolls toward it.** No float drift, trivial logic.
- **No physics engine for collision.** AABB overlap is faster, deterministic and unit-testable.
- **Camera uses fixed azimuth + fixed pitch, never `look_at`.** `look_at` couples the character's screen position to the look-target distance; every tweak forces a recompute.
- **Design difficulty in reaction time, not gap distance.** Spatial gaps must always exceed one full jump's travel distance or you create unbeatable combos.
- **Custom hitboxes.** An obstacle's collider is not always its visual bounds — support an `Area3D` + `BoxShape3D` named `HitBox` that overrides the merged mesh AABB.

## Verification loop

```
--headless --quit                     # zero script errors
--headless --script res://tests/...   # assertions, exit code 0
--write-movie out.avi --fixed-fps 30  # actual pixels
```

Headless has no renderer — **you cannot inspect visuals without `--write-movie`**.
Extract frames with ffmpeg and look at them. Several bugs (sunk wheels, jagged
edges, sky artifacts) are invisible in logs and obvious in a frame.

## Additional resources

- Detailed code, constants and a worked example: [reference.md](reference.md)
- Reusable mesh helpers: [templates/blender_loft.py](templates/blender_loft.py)
- Cel shader: [templates/toon3color.gdshader](templates/toon3color.gdshader)
- Outline shader: [templates/outline.gdshader](templates/outline.gdshader)
