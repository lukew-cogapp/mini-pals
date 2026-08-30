"""Report which atlas texels a Quaternius model's UVs sample.

Recolouring an atlas by eye greyed the cat once: every vertex on a monster
samples one texel, and the columns a model does NOT touch look identical in
the image. Run this before editing an atlas.

Usage: uv run --with pillow python scripts/tools/inspect_atlas.py \
           assets/monsters/Flying/Alpaking.gltf
"""

import argparse
import base64
import io
import json
import struct
from collections import Counter
from pathlib import Path

from PIL import Image

_CTYPE = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4), 5121: ("B", 1)}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _buffers(gltf: dict) -> list[bytes]:
    out = []
    for b in gltf["buffers"]:
        uri = b["uri"]
        if not uri.startswith("data:"):
            raise SystemExit(f"external buffer not supported: {uri}")
        out.append(base64.b64decode(uri.split(",", 1)[1]))
    return out


def _accessor(gltf: dict, bufs: list[bytes], index: int) -> list[float]:
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    data = bufs[view.get("buffer", 0)]
    off = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt, size = _CTYPE[acc["componentType"]]
    ncomp = _NCOMP[acc["type"]]
    stride = view.get("byteStride")
    if stride and stride != size * ncomp:
        vals: list[float] = []
        for k in range(acc["count"]):
            vals += list(struct.unpack_from(f"<{fmt * ncomp}", data, off + k * stride))
        return vals
    return list(struct.unpack_from(f"<{fmt * acc['count'] * ncomp}", data, off))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("gltf")
    ap.add_argument("--atlas", help="defaults to the gltf's own image uri")
    args = ap.parse_args()

    path = Path(args.gltf)
    gltf = json.loads(path.read_text())
    bufs = _buffers(gltf)
    image = gltf["images"][0]
    if args.atlas:
        atlas = Path(args.atlas)
        im = Image.open(atlas).convert("RGBA")
    elif "uri" in image:
        atlas = path.parent / image["uri"]
        im = Image.open(atlas).convert("RGBA")
    else:
        # Embedded in a bufferView, which is how this pack ships.
        view = gltf["bufferViews"][image["bufferView"]]
        off = view.get("byteOffset", 0)
        blob = bufs[view.get("buffer", 0)][off : off + view["byteLength"]]
        atlas = Path(f"(embedded {image.get('name', '')})")
        im = Image.open(io.BytesIO(blob)).convert("RGBA")
    w, h = im.size
    px = im.load()
    print(f"atlas {atlas} {w}x{h}")
    for y in range(h):
        print(f"  row {y}: " + " ".join("%02x%02x%02x" % px[x, y][:3] for x in range(w)))

    print("\nsampled texels, by mesh primitive:")
    for mesh in gltf["meshes"]:
        print(" ", mesh.get("name"))
        for i, prim in enumerate(mesh["primitives"]):
            uvs = _accessor(gltf, bufs, prim["attributes"]["TEXCOORD_0"])
            counts: Counter = Counter()
            for k in range(0, len(uvs), 2):
                x = min(w - 1, max(0, int(uvs[k] * w)))
                y = min(h - 1, max(0, int(uvs[k + 1] * h)))
                counts[(x, y, px[x, y][:3])] += 1
            print(f"    prim {i}: {len(uvs) // 2} verts")
            for (x, y, rgb), n in counts.most_common():
                print(f"      ({x},{y}) #{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}  {n} verts")

    print("\nanimations:", [a.get("name") for a in gltf.get("animations", [])])


if __name__ == "__main__":
    main()
