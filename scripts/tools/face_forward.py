"""Rotate Quaternius glTF models 180 degrees so they face Godot's forward.

The pack authors its monsters facing +Z. Godot's forward is -Z, so every
model would otherwise need a compensating transform at each place it is used,
which is what produced a run of facing bugs. Rotating each file's scene root
once, here, lets all game code use plain Godot conventions.

Idempotent: a model already carrying the flip is skipped.

Usage: python scripts/tools/face_forward.py assets/monsters
"""

import json
import pathlib
import sys

FLIP = [0.0, 1.0, 0.0, 0.0]  # quaternion, 180 degrees about Y


def flip(path: pathlib.Path) -> str:
    doc = json.loads(path.read_text())
    scene = doc["scenes"][doc.get("scene", 0)]
    changed = False
    for index in scene["nodes"]:
        node = doc["nodes"][index]
        if node.get("rotation") == FLIP:
            continue
        if "matrix" in node or "rotation" in node:
            return "skipped, root already has a transform"
        node["rotation"] = FLIP
        changed = True
    if not changed:
        return "already flipped"
    path.write_text(json.dumps(doc))
    return "flipped"


def main() -> None:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "assets/monsters")
    for path in sorted(root.rglob("*.gltf")):
        print(f"{path.relative_to(root)}: {flip(path)}")


if __name__ == "__main__":
    main()
