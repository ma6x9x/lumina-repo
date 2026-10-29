#!/usr/bin/env python3
"""Generate ORIGINAL placeholder era-styled icons for stock bundle IDs.

Every pixel is drawn here with PIL primitives. NO Apple artwork is used,
copied, traced or redistributed. The glyphs are original drawings that read
as the app they stand for. Skin authors who want true-to-Apple eras should
supply their own art or use the "real" icon flavour at runtime instead.

    pip install pillow
    python3 tools/sk1n-icons.py            # writes all three skins
    python3 tools/sk1n-icons.py ios7       # one skin
"""
import math
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 180          # @3x of 60pt; saved as <bundleid>.png (loader treats plain .png as @3x)
SS = 3              # supersample
ROOT = Path(__file__).resolve().parent.parent / "layout/Library/Sk1n/Skins"

# bundle id -> (label, base colour, glyph)
APPS = {
    "com.apple.mobilephone": ("Phone", (52, 199, 89), "phone"),
    "com.apple.MobileSMS": ("Messages", (52, 199, 89), "bubble"),
    "com.apple.mobilemail": ("Mail", (0, 122, 255), "envelope"),
    "com.apple.mobilesafari": ("Safari", (0, 122, 255), "compass"),
    "com.apple.Music": ("Music", (255, 59, 92), "note"),
    "com.apple.camera": ("Camera", (142, 142, 147), "camera"),
    "com.apple.mobileslideshow": ("Photos", (255, 204, 0), "flower"),
    "com.apple.Preferences": ("Settings", (142, 142, 147), "gear"),
    "com.apple.mobilecal": ("Calendar", (255, 69, 58), "grid"),
    "com.apple.mobiletimer": ("Clock", (40, 40, 44), "clock"),
    "com.apple.Maps": ("Maps", (52, 199, 89), "pin"),
    "com.apple.weather": ("Weather", (64, 156, 255), "sun"),
    "com.apple.mobilenotes": ("Notes", (255, 214, 10), "lines"),
    "com.apple.reminders": ("Reminders", (255, 255, 255), "check"),
    "com.apple.calculator": ("Calculator", (60, 60, 64), "plusminus"),
    "com.apple.AppStore": ("App Store", (10, 132, 255), "a"),
    "com.apple.Health": ("Health", (255, 255, 255), "heart"),
    "com.apple.Passbook": ("Wallet", (30, 30, 34), "card"),
    "com.apple.stocks": ("Stocks", (20, 20, 24), "chart"),
    "com.apple.facetime": ("FaceTime", (52, 199, 89), "video"),
    "com.apple.news": ("News", (255, 69, 58), "n"),
    "com.apple.VoiceMemos": ("Voice Memos", (28, 28, 30), "wave"),
    "com.apple.mobilegarageband": ("GarageBand", (255, 149, 0), "guitar"),
    "com.apple.Home": ("Home", (255, 159, 10), "house"),
}

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c)

def solid(w, h, col):
    im = Image.new("RGBA", (w, h), col + (255,))
    return im

def rmask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    return m

def rot_rect(d, cx, cy, w, h, angle, col):
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for x, y in ((-w/2, -h/2), (w/2, -h/2), (w/2, h/2), (-w/2, h/2)):
        pts.append((cx + x*ca - y*sa, cy + x*sa + y*ca))
    d.polygon(pts, fill=col)

def glyph(d, kind, cx, cy, s, col, w):
    """Clean geometric glyphs sized for the flat iOS 7 look."""
    L = max(3, int(s * 0.085))
    if kind == "phone":
        # simple handset silhouette
        d.ellipse((cx - s*.38, cy - s*.38, cx - s*.08, cy - s*.08), fill=col)
        d.ellipse((cx + s*.08, cy + s*.08, cx + s*.38, cy + s*.38), fill=col)
        rot_rect(d, cx, cy, s*.55, s*.16, math.radians(45), col)
    elif kind == "bubble":
        d.rounded_rectangle((cx - s*.40, cy - s*.32, cx + s*.40, cy + s*.18),
                            int(s*.18), fill=col)
        d.polygon([(cx - s*.18, cy + s*.10), (cx + s*.02, cy + s*.10),
                   (cx - s*.14, cy + s*.38)], fill=col)
    elif kind == "envelope":
        d.rounded_rectangle((cx - s*.40, cy - s*.26, cx + s*.40, cy + s*.26),
                            int(s*.06), fill=col)
        d.line([(cx - s*.38, cy - s*.22), (cx, cy + s*.04), (cx + s*.38, cy - s*.22)],
               fill=(40, 40, 44, 255), width=L)
    elif kind == "compass":
        d.ellipse((cx - s*.38, cy - s*.38, cx + s*.38, cy + s*.38), outline=col, width=L+1)
        d.polygon([(cx + s*.26, cy - s*.26), (cx - s*.02, cy - s*.04), (cx + s*.04, cy + s*.02)], fill=col)
        d.polygon([(cx - s*.26, cy + s*.26), (cx + s*.02, cy + s*.04), (cx - s*.04, cy - s*.02)],
                  fill=tuple(max(0, int(c * 0.55)) for c in col))
        d.ellipse((cx - s*.05, cy - s*.05, cx + s*.05, cy + s*.05), fill=col)
    elif kind == "note":
        d.ellipse((cx - s*.30, cy + s*.10, cx - s*.06, cy + s*.34), fill=col)
        d.ellipse((cx + s*.10, cy + s*.02, cx + s*.34, cy + s*.26), fill=col)
        d.rectangle((cx - s*.11, cy - s*.32, cx - s*.07, cy + s*.24), fill=col)
        d.rectangle((cx + s*.29, cy - s*.40, cx + s*.33, cy + s*.16), fill=col)
        d.polygon([(cx - s*.11, cy - s*.32), (cx + s*.33, cy - s*.40),
                   (cx + s*.33, cy - s*.22), (cx - s*.11, cy - s*.14)], fill=col)
    elif kind == "camera":
        d.rounded_rectangle((cx - s*.42, cy - s*.24, cx + s*.42, cy + s*.28),
                            int(s*.08), fill=col)
        d.rounded_rectangle((cx - s*.12, cy - s*.36, cx + s*.04, cy - s*.18),
                            int(s*.04), fill=col)
        d.ellipse((cx - s*.16, cy - s*.10, cx + s*.16, cy + s*.22),
                  outline=(40, 40, 44, 255), width=L)
    elif kind == "flower":
        for i in range(6):
            a = i * math.pi / 3
            x, y = cx + math.cos(a) * s*.22, cy + math.sin(a) * s*.22
            d.ellipse((x - s*.14, y - s*.14, x + s*.14, y + s*.14), fill=col)
        d.ellipse((cx - s*.10, cy - s*.10, cx + s*.10, cy + s*.10), fill=col)
    elif kind == "gear":
        for i in range(8):
            a = i * math.pi / 4
            x, y = cx + math.cos(a) * s*.38, cy + math.sin(a) * s*.38
            rot_rect(d, x, y, s*.22, s*.18, a, col)
        d.ellipse((cx - s*.30, cy - s*.30, cx + s*.30, cy + s*.30), outline=col, width=int(s*.08))
        d.ellipse((cx - s*.12, cy - s*.12, cx + s*.12, cy + s*.12), fill=col)
    elif kind == "grid":
        d.rounded_rectangle((cx - s*.36, cy - s*.40, cx + s*.36, cy + s*.40),
                            int(s*.07), fill=col)
        d.line([(cx - s*.36, cy - s*.18), (cx + s*.36, cy - s*.18)],
               fill=(40, 40, 44, 255), width=L)
        for j in range(3):
            for i in range(4):
                x = cx - s*.24 + i * s*.16
                y = cy - s*.04 + j * s*.14
                d.ellipse((x - s*.035, y - s*.035, x + s*.035, y + s*.035), fill=(40, 40, 44, 255))
    elif kind == "clock":
        d.ellipse((cx - s*.40, cy - s*.40, cx + s*.40, cy + s*.40),
                  outline=col, width=L+2)
        d.line([(cx, cy), (cx, cy - s*.26)], fill=col, width=L)
        d.line([(cx, cy), (cx + s*.20, cy + s*.04)], fill=col, width=L)
        d.ellipse((cx - s*.04, cy - s*.04, cx + s*.04, cy + s*.04), fill=col)
    elif kind == "pin":
        d.ellipse((cx - s*.28, cy - s*.42, cx + s*.28, cy + s*.14), fill=col)
        d.polygon([(cx - s*.20, cy - s*.02), (cx + s*.20, cy - s*.02),
                   (cx, cy + s*.42)], fill=col)
    elif kind == "sun":
        d.ellipse((cx - s*.20, cy - s*.20, cx + s*.20, cy + s*.20), fill=col)
        for i in range(12):
            a = i * math.pi / 6
            x0 = cx + math.cos(a) * s*.30
            y0 = cy + math.sin(a) * s*.30
            x1 = cx + math.cos(a) * s*.40
            y1 = cy + math.sin(a) * s*.40
            d.line([(x0, y0), (x1, y1)], fill=col, width=L)
    elif kind == "lines":
        for k in (-1, 0, 1):
            d.rounded_rectangle((cx - s*.34, cy + k*s*.22 - L//2, cx + s*.34, cy + k*s*.22 + L//2),
                                L//2, fill=col)
    elif kind == "check":
        d.line([(cx - s*.28, cy + s*.02), (cx - s*.06, cy + s*.24), (cx + s*.30, cy - s*.24)],
               fill=col, width=L+1)
    elif kind == "plusminus":
        for i in (-1, 1):
            for j in (-1, 1):
                d.rounded_rectangle((cx + i*s*.22 - s*.14, cy + j*s*.22 - s*.14,
                                     cx + i*s*.22 + s*.14, cy + j*s*.22 + s*.14),
                                    int(s*.04), fill=col)
    elif kind == "a":
        d.line([(cx - s*.28, cy + s*.30), (cx, cy - s*.30), (cx + s*.28, cy + s*.30)],
               fill=col, width=L+1)
        d.line([(cx - s*.16, cy + s*.04), (cx + s*.16, cy + s*.04)], fill=col, width=L)
    elif kind == "heart":
        d.ellipse((cx - s*.38, cy - s*.34, cx + s*.02, cy + s*.06), fill=col)
        d.ellipse((cx - s*.02, cy - s*.34, cx + s*.38, cy + s*.06), fill=col)
        d.polygon([(cx - s*.32, cy - s*.08), (cx + s*.32, cy - s*.08),
                   (cx, cy + s*.38)], fill=col)
    elif kind == "card":
        d.rounded_rectangle((cx - s*.32, cy - s*.34, cx + s*.32, cy - s*.06),
                            int(s*.05), fill=col)
        d.rounded_rectangle((cx - s*.40, cy - s*.16, cx + s*.40, cy + s*.12),
                            int(s*.05), fill=col)
        d.rounded_rectangle((cx - s*.32, cy + s*.02, cx + s*.32, cy + s*.34),
                            int(s*.05), outline=col, width=L)
    elif kind == "chart":
        d.line([(cx - s*.38, cy + s*.20), (cx - s*.08, cy - s*.06),
                (cx + s*.12, cy + s*.08), (cx + s*.38, cy - s*.28)],
               fill=col, width=L)
    elif kind == "video":
        d.rounded_rectangle((cx - s*.40, cy - s*.20, cx + s*.10, cy + s*.20),
                            int(s*.05), fill=col)
        d.polygon([(cx + s*.16, cy), (cx + s*.40, cy - s*.16),
                   (cx + s*.40, cy + s*.16)], fill=col)
    elif kind == "n":
        d.line([(cx - s*.26, cy + s*.32), (cx - s*.26, cy - s*.32)], fill=col, width=L)
        d.line([(cx + s*.26, cy + s*.32), (cx + s*.26, cy - s*.32)], fill=col, width=L)
        d.line([(cx - s*.26, cy - s*.32), (cx + s*.26, cy + s*.32)], fill=col, width=L)
    elif kind == "wave":
        for i, hh in enumerate((.10, .24, .38, .24, .10, .28, .16)):
            x = cx - s*.34 + i * s*.11
            d.line([(x, cy - s*hh), (x, cy + s*hh)], fill=col, width=max(2, L-1))
    elif kind == "house":
        d.polygon([(cx - s*.40, cy - s*.02), (cx, cy - s*.40), (cx + s*.40, cy - s*.02)], fill=col)
        d.rectangle((cx - s*.28, cy - s*.02, cx + s*.28, cy + s*.34), fill=col)
        d.rounded_rectangle((cx - s*.09, cy + s*.08, cx + s*.09, cy + s*.34),
                            s*.03, fill=tuple(max(0, int(c * 0.35)) for c in col))
    elif kind == "guitar":
        rot_rect(d, cx + s*.10, cy - s*.10, s*.74, s*.10, math.radians(-45), col)
        d.ellipse((cx - s*.30, cy - s*.04, cx + s*.14, cy + s*.40), fill=col)
        d.ellipse((cx - s*.18, cy + s*.06, cx + s*.26, cy + s*.44), fill=col)
        d.ellipse((cx - s*.07, cy + s*.10, cx + s*.07, cy + s*.24), fill=(40, 40, 44, 255))
    else:
        d.line([(cx - s*.24, cy + s*.28), (cx, cy - s*.28), (cx + s*.24, cy + s*.28)],
               fill=col, width=L)
        d.line([(cx - s*.12, cy + s*.06), (cx + s*.12, cy + s*.06)], fill=col, width=L)

def render(era, base, kind):
    N = SIZE * SS
    r = int(N * 0.22)
    mask = rmask(N, N, r)
    if era == "ios1":
        top, bot = shade(base, 1.25), shade(base, 0.62)
        im = Image.new("RGBA", (N, N))
        px = im.load()
        for y in range(N):
            c = lerp(top, bot, y / max(1, N - 1)) + (255,)
            for x in range(N): px[x, y] = c
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, N-1, N-1), r, outline=(255, 255, 255, 60), width=SS*2)
        glyph_col = (255, 255, 255, 245)
        glyph(d, kind, N/2, N/2, N*.60, glyph_col, SS)
        gl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(gl).ellipse((-N*.25, -N*.55, N*1.25, N*.52), fill=(255, 255, 255, 70))
        im = Image.alpha_composite(im, gl)
    elif era == "ios7":
        # Pure flat solid fill — matches real iOS 7 reference sheets
        im = solid(N, N, base)
        d = ImageDraw.Draw(im)
        glyph(d, kind, N/2, N/2, N*.58, (255, 255, 255, 255), SS)
    else:  # glass27 — not shipped, but kept for completeness
        im = solid(N, N, shade(base, 0.7))
        glyph(ImageDraw.Draw(im), kind, N/2, N/2, N*.56, (255, 255, 255, 230), SS)
    im.putalpha(mask)
    return im.resize((SIZE, SIZE), Image.LANCZOS)

def main():
    eras = sys.argv[1:] or ["ios1", "ios7"]
    for era in eras:
        out = ROOT / era / "Icons"
        out.mkdir(parents=True, exist_ok=True)
        for bid, (label, base, kind) in APPS.items():
            render(era, base, kind).save(out / f"{bid}.png", optimize=True)
        print(f"{era}: {len(APPS)} icons -> {out}")

if __name__ == "__main__":
    main()
