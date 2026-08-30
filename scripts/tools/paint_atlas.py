"""Paint named texels of a Quaternius atlas, leaving every other one alone.

A Quaternius monster samples a handful of texels out of a shared atlas, so a
whole-image hue shift recolours columns the model never reads and misses the
ones it does. Run inspect_atlas.py first to learn the coordinates, then name
them here.

Usage:
  uv run --with pillow python scripts/tools/paint_atlas.py IN.png OUT.png \
      2,22=ff9ecb 3,22=e0679f 4,22=ffd6e8
"""

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("paint", nargs="+", help="x,y=rrggbb")
    args = ap.parse_args()

    im = Image.open(args.src).convert("RGBA")
    px = im.load()
    for spec in args.paint:
        where, _, hexrgb = spec.partition("=")
        x, y = (int(v) for v in where.split(","))
        rgb = tuple(int(hexrgb[i : i + 2], 16) for i in (0, 2, 4))
        was = px[x, y]
        px[x, y] = (*rgb, was[3])
        print(f"({x},{y}) #{was[0]:02x}{was[1]:02x}{was[2]:02x} -> #{hexrgb}")
    Path(args.dst).parent.mkdir(parents=True, exist_ok=True)
    im.save(args.dst)
    print(f"wrote {args.dst}")


if __name__ == "__main__":
    main()
