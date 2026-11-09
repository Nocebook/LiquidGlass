#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 liquid (HL) 图标：液态玻璃方块 + 悬浮液滴。

纯代码绘制，输出多尺寸 PNG：
  icon-1024.png   母版
  icon-512.png    Sileo 源图标（CydiaIcon）
  icon@3x.png     87x87  PreferenceLoader
  icon@2x.png     58x58  PreferenceLoader
  icon.png        29x29

用法：python tools/make_icon.py
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "icon-build")


# ---------- 基础 ----------

def cubic(p0, p1, p2, p3, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append((
            u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1],
        ))
    return pts


def arc(cx, cy, r, a0, a1, steps):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / steps)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / steps)))
            for i in range(steps + 1)]


def gradient(size, c0, c1, angle=130):
    """对角线性渐变：小图逐像素，再放大。"""
    small = 192
    img = Image.new("RGB", (small, small))
    px = img.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    proj = [0, (small - 1) * dx, (small - 1) * dy,
            (small - 1) * dx + (small - 1) * dy]
    lo, hi = min(proj), max(proj)
    span = (hi - lo) or 1
    for y in range(small):
        for x in range(small):
            t = (x * dx + y * dy - lo) / span
            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
            px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return img.resize((size, size), Image.LANCZOS).convert("RGBA")


def glow(size, center, radius, color, peak, power=2.1):
    small = 220
    lum = Image.new("L", (small, small), 0)
    px = lum.load()
    cx, cy = center[0] / size * small, center[1] / size * small
    rr = max(radius / size * small, 1e-6)
    for y in range(small):
        for x in range(small):
            d = math.hypot(x - cx, y - cy) / rr
            if d < 1:
                px[x, y] = int((1 - d) ** power * peak)
    layer = Image.new("RGBA", (size, size), color + (0,))
    layer.putalpha(lum.resize((size, size), Image.LANCZOS))
    return layer


def vertical_alpha(size, top_a, bottom_a):
    """垂直 alpha 渐变遮罩。"""
    small = 128
    lum = Image.new("L", (small, small))
    px = lum.load()
    for y in range(small):
        v = int(top_a + (bottom_a - top_a) * y / (small - 1))
        for x in range(small):
            px[x, y] = v
    return lum.resize((size, size), Image.LANCZOS)


def teardrop(cx, cy, r, tip_y):
    """瘦长水滴：肩线接近直线，下方圆弧饱满。"""
    h = cy - tip_y
    pts = []
    pts += cubic((cx, tip_y),
                 (cx + r * 0.20, tip_y + h * 0.30),
                 (cx + r * 0.80, cy - r * 0.92),
                 (cx + r, cy), 110)
    pts += arc(cx, cy, r, 0, 180, 170)
    pts += cubic((cx - r, cy),
                 (cx - r * 0.80, cy - r * 0.92),
                 (cx - r * 0.20, tip_y + h * 0.30),
                 (cx, tip_y), 110)
    return pts


# ---------- 绘制 ----------

def build():
    # 1) 背景：更深，让水滴跳出来
    bg = gradient(S, (5, 17, 30), (10, 52, 78), 132)

    # 底部青色液光
    bg.alpha_composite(glow(S, (S * 0.5, S * 1.05), S * 0.80, (40, 190, 224), 110))
    # 左上冷白受光
    bg.alpha_composite(glow(S, (S * 0.24, S * 0.06), S * 0.66, (255, 255, 255), 52))

    # 玻璃内部斜亮带
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(band).polygon(
        [(0, S * 0.70), (S, S * 0.26), (S, S * 0.40), (0, S * 0.86)],
        fill=(190, 240, 255, 16))
    bg.alpha_composite(band.filter(ImageFilter.GaussianBlur(S * 0.025)))

    radius = int(S * 0.2237)
    body_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(body_mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(bg, (0, 0), body_mask)

    # 2) 水滴几何：宽高比约 0.57
    cx, cy, r = S * 0.5, S * 0.615, S * 0.185
    tip_y = S * 0.155
    pts = teardrop(cx, cy, r, tip_y)

    drop_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(drop_mask).polygon(pts, fill=255)
    drop_mask = drop_mask.filter(ImageFilter.GaussianBlur(1.0))

    # 3) 投影：向下偏移、放大模糊
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(drop_mask.filter(ImageFilter.GaussianBlur(S * 0.042))
                .point(lambda v: int(v * 0.55)))
    tinted = Image.new("RGBA", (S, S), (2, 14, 24, 255))
    tinted.putalpha(sh.split()[3])
    icon.alpha_composite(tinted, (0, int(S * 0.052)))

    # 4) 水滴主体：半透明玻璃，背景能透过来才像液体
    fill = gradient(S, (248, 253, 255), (126, 208, 236), 100)

    # 内部只有一条柔和折射带，别的东西靠边缘光来做
    band2 = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(band2).polygon(
        [(cx - r * 1.1, cy + r * 0.30), (cx + r * 1.1, cy - r * 0.46),
         (cx + r * 1.1, cy - r * 0.14), (cx - r * 1.1, cy + r * 0.62)],
        fill=(255, 255, 255, 46))
    fill.alpha_composite(band2.filter(ImageFilter.GaussianBlur(S * 0.028)))

    # 底部液体堆叠，偏青
    low = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(low).ellipse(
        [cx - r * 0.82, cy + r * 0.30, cx + r * 0.82, cy + r * 1.10],
        fill=(58, 172, 208, 62))
    fill.alpha_composite(low.filter(ImageFilter.GaussianBlur(S * 0.042)))

    drop = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # 78% 不透明度：背景的斜亮带会从水滴里透出来，但整体仍明显亮于背景
    drop.paste(fill, (0, 0), drop_mask.point(lambda v: int(v * 0.78)))

    # 4.5) 内部液面：玻璃球里存着液体，这条弧线最能说明"液"
    liquid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    lq = ImageDraw.Draw(liquid)
    level_top = cy + r * 0.16
    lq.ellipse([cx - r * 1.05, level_top, cx + r * 1.05, cy + r * 2.10],
               fill=(96, 200, 232, 100))
    lq.ellipse([cx - r * 1.05, level_top, cx + r * 1.05, cy + r * 0.80],
               outline=(228, 251, 255, 115), width=3)
    liquid = liquid.filter(ImageFilter.GaussianBlur(S * 0.009))
    liquid.putalpha(Image.composite(liquid.split()[3], Image.new("L", (S, S), 0),
                                    drop_mask.point(lambda v: 255 if v > 70 else 0)))
    drop.alpha_composite(liquid)

    # 5) 厚玻璃边缘：一圈不透明的亮边，左上加一段更强的受光
    # 环 = 原 mask 减去腐蚀后的 mask（写反会让白色铺满整个水滴内部）
    ring_mask = ImageChops.subtract(drop_mask, drop_mask.filter(ImageFilter.MinFilter(25)))

    # 上半部分遮罩（左上受光区）
    top_lum = Image.new("L", (S, S), 0)
    ImageDraw.Draw(top_lum).ellipse(
        [cx - r * 1.3, cy - r * 2.0, cx + r * 0.85, cy + r * 0.35], fill=255)
    top_lum = top_lum.filter(ImageFilter.GaussianBlur(S * 0.03))

    rim_base = ring_mask.point(lambda v: int(v * 0.55))
    rim_top = Image.composite(ring_mask, Image.new("L", (S, S), 0), top_lum)
    rim_lum = Image.composite(Image.new("L", (S, S), 245),
                              rim_base, rim_top.point(lambda v: 255 if v > 30 else 0))
    rim = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    rim.putalpha(rim_lum.filter(ImageFilter.GaussianBlur(S * 0.0035)))
    drop.alpha_composite(rim)

    # 6) 水滴轮廓细线
    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).line(pts + [pts[0]], fill=(255, 255, 255, 120),
                              width=2, joint="curve")
    edge = edge.filter(ImageFilter.GaussianBlur(0.5))
    edge.putalpha(Image.composite(edge.split()[3], Image.new("L", (S, S), 0),
                                  drop_mask.filter(ImageFilter.MaxFilter(5))))
    drop.alpha_composite(edge)

    icon.alpha_composite(drop)

    # 7) 液面波纹：水滴落在液面上的一圈涟漪，要露在水滴外侧
    ripple = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ripple)
    rd.ellipse([cx - r * 1.92, cy + r * 1.10, cx + r * 1.92, cy + r * 1.62],
               outline=(220, 250, 255, 92), width=4)
    rd.ellipse([cx - r * 1.34, cy + r * 1.16, cx + r * 1.34, cy + r * 1.52],
               outline=(255, 255, 255, 62), width=3)
    icon.alpha_composite(ripple.filter(ImageFilter.GaussianBlur(4.5)))

    # 8) 外框玻璃折光
    rim2 = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d2 = ImageDraw.Draw(rim2)
    d2.rounded_rectangle([2, 2, S - 3, S - 3], radius=radius - 2,
                         outline=(255, 255, 255, 78), width=4)
    d2.rounded_rectangle([12, 12, S - 13, S - 13], radius=radius - 12,
                         outline=(255, 255, 255, 22), width=2)
    icon.alpha_composite(rim2.filter(ImageFilter.GaussianBlur(1.2)))

    # 9) 顶端整体柔光
    icon.alpha_composite(glow(S, (S * 0.5, -S * 0.10), S * 0.80, (255, 255, 255), 30))

    return icon


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    master = build()
    master.save(os.path.join(OUT_DIR, "icon-1024.png"))
    print("母版 icon-1024.png")
    for name, px, sharpen in [("icon-512.png", 512, 0), ("icon@3x.png", 87, 70),
                              ("icon@2x.png", 58, 70), ("icon.png", 29, 50)]:
        img = master.resize((px, px), Image.LANCZOS)
        if sharpen:
            img = img.filter(ImageFilter.UnsharpMask(radius=1.0, percent=sharpen, threshold=2))
        img.save(os.path.join(OUT_DIR, name))
        print("  %-14s %dx%d" % (name, px, px))


if __name__ == "__main__":
    main()
