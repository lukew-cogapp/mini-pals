"""Recolour a Quaternius atlas by shifting hue and boosting saturation.

The packs ship one small atlas per monster, so a recoloured copy is the
cheapest way to reskin one without touching the shared source art.

Usage: uv run --with pillow python scripts/tools/recolour_texture.py \
           IN.png OUT.png --hue 0.58 --sat 1.4
"""

import argparse
import colorsys

from PIL import Image


def recolour(src: str, dst: str, hue: float, sat: float, keep_white: bool) -> None:
    im = Image.open(src).convert("RGBA")
    out = []
    for r, g, b, a in im.getdata():
        h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
        # White and near-black carry eyes and outlines; recolouring them
        # muddies the face.
        if keep_white and (l > 0.95 or l < 0.12):
            out.append((r, g, b, a))
            continue
        nr, ng, nb = colorsys.hls_to_rgb(hue, l, min(1.0, max(s, 0.25) * sat))
        out.append((round(nr * 255), round(ng * 255), round(nb * 255), a))
    im.putdata(out)
    im.save(dst)
    print(f"wrote {dst} ({im.size[0]}x{im.size[1]})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--hue", type=float, default=0.58, help="0-1, 0.58 is blue")
    ap.add_argument("--sat", type=float, default=1.4)
    ap.add_argument("--recolour-all", action="store_true")
    a = ap.parse_args()
    recolour(a.src, a.dst, a.hue, a.sat, not a.recolour_all)


if __name__ == "__main__":
    main()
