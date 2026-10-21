#!/usr/bin/env python3
"""Generate ORIGINAL placeholder era-styled icons for stock bundle IDs.

Every pixel is drawn here with PIL primitives (rounded rectangles, rotated
shapes, simple geometric glyphs). NO Apple artwork is used, copied, traced or
redistributed. The glyphs are original drawings that read as the app they
stand for (handset, compass pointer, guitar body, ...); skin authors who want
true-to-Apple eras should supply their own art or use the "real" icon flavour
at runtime instead.

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

def vgrad(w, h, top, bot):
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        c = lerp(top, bot, y / max(1, h - 1)) + (255,)
        for x in range(w): px[x, y] = c
    return im

def rmask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), r, fill=255)
    return m

def rot_rect(d, cx, cy, w, h, angle, col):
    """A filled rectangle rotated about (cx, cy) — for hands, teeth, handsets."""
    ca, sa = math.cos(angle), math.sin(angle)
    pts = []
    for x, y in ((-w/2, -h/2), (w/2, -h/2), (w/2, h/2), (-w/2, h/2)):
        pts.append((cx + x*ca - y*sa, cy + x*sa + y*ca))
    d.polygon(pts, fill=col)

def glyph(d, kind, cx, cy, s, col, w):
    """Recognisable, ORIGINAL glyphs for each app, drawn with PIL primitives."""
    L = max(2, int(s * 0.07))
    if kind in ("phone",):          # handset: two earpads joined by a thick bar
        for sx in (-1, 1):
            d.ellipse((cx + sx*s*.28 - s*.17, cy + sx*s*.28 - s*.17,
                       cx + sx*s*.28 + s*.17, cy + sx*s*.28 + s*.17), fill=col)
        rot_rect(d, cx, cy, s * 0.62, s * 0.17, math.radians(45), col)
    elif kind in ("bubble",):       # speech bubble: pill + tail
        d.rounded_rectangle((cx - s*.42, cy - s*.34, cx + s*.42, cy + s*.22),
                            int(s*.20), fill=col)
        d.polygon([(cx - s*.20, cy + s*.14), (cx + s*.04, cy + s*.14),
                   (cx - s*.16, cy + s*.42)], fill=col)
    elif kind in ("envelope",):     # envelope: sheet + flap V
        d.rounded_rectangle((cx - s*.42, cy - s*.28, cx + s*.42, cy + s*.28),
                            int(s*.07), fill=col)
        for t in (-0.26, 0.04):
            pass
        d.line([(cx - s*.40, cy - s*.24), (cx, cy + s*.06), (cx + s*.40, cy - s*.24)],
               fill=(58, 58, 62, 255), width=L)
    elif kind in ("compass",):      # compass rose: ring, needle, hub
        d.ellipse((cx - s*.40, cy - s*.40, cx + s*.40, cy + s*.40), outline=col, width=int(L*1.5))
        d.polygon([(cx + s*.28, cy - s*.28), (cx - s*.03, cy - s*.05), (cx + s*.05, cy + s*.03)], fill=col)
        d.polygon([(cx - s*.28, cy + s*.28), (cx + s*.03, cy + s*.05), (cx - s*.05, cy - s*.03)],
                  fill=tuple(max(0, int(c * 0.55)) for c in col))
        d.ellipse((cx - s*.04, cy - s*.04, cx + s*.04, cy + s*.04), fill=col)
    elif kind in ("note",):         # two beamed eighth notes
        d.ellipse((cx - s*.32, cy + s*.12, cx - s*.08, cy + s*.36), fill=col)
        d.ellipse((cx + s*.08, cy + s*.04, cx + s*.32, cy + s*.28), fill=col)
        d.rectangle((cx - s*.13, cy - s*.34, cx - s*.09, cy + s*.26), fill=col)
        d.rectangle((cx + s*.27, cy - s*.42, cx + s*.31, cy + s*.18), fill=col)
        d.polygon([(cx - s*.13, cy - s*.34), (cx + s*.31, cy - s*.42),
                   (cx + s*.31, cy - s*.24), (cx - s*.13, cy - s*.16)], fill=col)
    elif kind in ("camera",):       # camera body, shutter bump, lens
        d.rounded_rectangle((cx - s*.44, cy - s*.26, cx + s*.44, cy + s*.30),
                            int(s*.09), fill=col)
        d.rounded_rectangle((cx - s*.14, cy - s*.38, cx + s*.06, cy - s*.20),
                            int(s*.05), fill=col)
        d.ellipse((cx - s*.17, cy - s*.11, cx + s*.17, cy + s*.25),
                  outline=(40, 40, 44, 255), width=int(L*1.5))
    elif kind in ("flower",):       # 8 petals around a center
        for i in range(8):
            a = i * math.pi / 4
            x, y = cx + math.cos(a) * s*.24, cy + math.sin(a) * s*.24
            d.ellipse((x - s*.15, y - s*.15, x + s*.15, y + s*.15), fill=col)
        d.ellipse((cx - s*.09, cy - s*.09, cx + s*.09, cy + s*.09), fill=col)
    elif kind in ("gear",):         # gear: teeth + ring + hub
        for i in range(8):
            a = i * math.pi / 4
            x, y = cx + math.cos(a) * s*.40, cy + math.sin(a) * s*.40
            rot_rect(d, x, y, s*.24, s*.20, a, col)
        d.ellipse((cx - s*.32, cy - s*.32, cx + s*.32, cy + s*.32), outline=col, width=int(s*.09))
        d.ellipse((cx - s*.14, cy - s*.14, cx + s*.14, cy + s*.14), fill=col)
    elif kind in ("grid",):         # calendar sheet: header + date dots
        d.rounded_rectangle((cx - s*.38, cy - s*.42, cx + s*.38, cy + s*.42),
                            int(s*.08), fill=col)
        d.line([(cx - s*.38, cy - s*.20), (cx + s*.38, cy - s*.20)],
               fill=(58, 58, 62, 255), width=L)
        for j, r in enumerate((-1, 0, 1)):
            for i in (-2, -1, 0, 1):
                y0 = cy + r*s*.12 + (s*.04 if j == -1 else 0)
                d.ellipse((cx + i*s*.13 - s*.04, y0 - s*.04,
                           cx + i*s*.13 + s*.04, y0 + s*.04), fill=(58, 58, 62, 255))
    elif kind in ("clock",):        # clock face: ring, minute hand, hour hand
        d.ellipse((cx - s*.42, cy - s*.42, cx + s*.42, cy + s*.42),
                  outline=col, width=int(L*2))
        d.line([(cx, cy), (cx, cy - s*.28)], fill=col, width=int(L*1.8))
        d.line([(cx, cy), (cx + s*.22, cy + s*.06)], fill=col, width=int(L*1.8))
    elif kind in ("pin",):          # map pin
        d.ellipse((cx - s*.30, cy - s*.44, cx + s*.30, cy + s*.16), fill=col)
        d.polygon([(cx - s*.22, cy - s*.02), (cx + s*.22, cy - s*.02),
                   (cx, cy + s*.44)], fill=col)
    elif kind in ("sun",):          # sun with rays
        d.ellipse((cx - s*.22, cy - s*.22, cx + s*.22, cy + s*.22), fill=col)
        for i in range(12):
            a = i * math.pi / 6
            x0, y0 = cx + math.cos(a)*s*.32, cy + math.sin(a)*s*.32
            x1, y1 = cx + math.cos(a)*s*.42, cy + math.sin(a)*s*.42
            d.line([(x0, y0), (x1, y1)], fill=col, width=L)
    elif kind in ("lines",):        # note paper: three ruled lines
        for k in (-1, 0, 1):
            d.rounded_rectangle((cx - s*.36, cy + k*s*.24 - L/2, cx + s*.36, cy + k*s*.24 + L/2),
                                L//2, fill=col)
    elif kind in ("check",):        # checklist
        d.line([(cx - s*.30, cy + s*.02), (cx - s*.08, cy + s*.26), (cx + s*.32, cy - s*.26)],
               fill=col, width=int(L*1.8))
    elif kind in ("plusminus",):    # calculator keys: 2x2 button grid
        for i in (-1, 1):
            for j in (-1, 1):
                d.rounded_rectangle((cx + i*s*.24 - s*.16, cy + j*s*.24 - s*.16,
                                     cx + i*s*.24 + s*.16, cy + j*s*.24 + s*.16),
                                    int(s*.05), fill=col)
    elif kind in ("a",):            # stylised "A" for the App Store
        d.line([(cx - s*.30, cy + s*.32), (cx, cy - s*.32),
                (cx + s*.30, cy + s*.32)], fill=col, width=int(L*1.8))
        d.line([(cx - s*.18, cy + s*.04), (cx + s*.18, cy + s*.04)], fill=col, width=int(L*1.4))
    elif kind in ("heart",):        # heart: two lobes + wedge point
        d.ellipse((cx - s*.40, cy - s*.36, cx + s*.02, cy + s*.06), fill=col)
        d.ellipse((cx - s*.02, cy - s*.36, cx + s*.40, cy + s*.06), fill=col)
        d.polygon([(cx - s*.34, cy - s*.10), (cx + s*.34, cy - s*.10),
                   (cx, cy + s*.40)], fill=col)
    elif kind in ("card",):         # wallet: stacked cards
        d.rounded_rectangle((cx - s*.34, cy - s*.36, cx + s*.34, cy - s*.08),
                            int(s*.06), fill=col)
        d.rounded_rectangle((cx - s*.42, cy - s*.18, cx + s*.42, cy + s*.10),
                            int(s*.06), fill=col)
        d.rounded_rectangle((cx - s*.34, cy + s*.00, cx + s*.34, cy + s*.36),
                            int(s*.06), outline=col, width=L)
    elif kind in ("chart",):        # line chart
        d.line([(cx - s*.40, cy + s*.22), (cx - s*.10, cy - s*.04),
                (cx + s*.10, cy + s*.10), (cx + s*.40, cy - s*.30)],
               fill=col, width=L)
    elif kind in ("video",):        # camera: body + prism
        d.rounded_rectangle((cx - s*.42, cy - s*.22, cx + s*.12, cy + s*.22),
                            int(s*.06), fill=col)
        d.polygon([(cx + s*.18, cy), (cx + s*.42, cy - s*.18),
                   (cx + s*.42, cy + s*.18)], fill=col)
    elif kind in ("n",):            # "N": two stems + diagonal
        d.line([(cx - s*.28, cy + s*.34), (cx - s*.28, cy - s*.34)], fill=col, width=int(L*1.5))
        d.line([(cx + s*.28, cy + s*.34), (cx + s*.28, cy - s*.34)], fill=col, width=int(L*1.5))
        d.line([(cx - s*.28, cy - s*.34), (cx + s*.28, cy + s*.34)], fill=col, width=int(L*1.5))
    elif kind in ("wave",):         # waveform bars
        for i, hh in enumerate((.12, .26, .40, .26, .12, .30, .18)):
            x = cx - s*.36 + i*s*.12
            d.line([(x, cy - s*hh), (x, cy + s*hh)], fill=col, width=int(L*0.9) or 2)
    elif kind in ("house",):        # home: roof + body + door
        d.polygon([(cx - s*.42, cy - s*.02), (cx, cy - s*.42), (cx + s*.42, cy - s*.02)], fill=col)
        d.rectangle((cx - s*.30, cy - s*.04, cx + s*.30, cy + s*.36), fill=col)
        d.rounded_rectangle((cx - s*.10, cy + s*.08, cx + s*.10, cy + s*.36),
                            s*.04, fill=tuple(max(0, int(c * 0.35)) for c in col))
    elif kind in ("guitar",):       # guitar: body under the neck, neck through it
        rot_rect(d, cx + s*.12, cy - s*.12, s*.78, s*.11, math.radians(-45), col)
        d.ellipse((cx - s*.32, cy - s*.06, cx + s*.16, cy + s*.42), fill=col)
        d.ellipse((cx - s*.20, cy + s*.04, cx + s*.28, cy + s*.46), fill=col)
        d.ellipse((cx - s*.08, cy + s*.08, cx + s*.08, cy + s*.24), fill=(58, 58, 62, 255))
        d.ellipse((cx - s*.13, cy + s*.03, cx + s*.13, cy + s*.29), outline=(58, 58, 62, 255), width=L)
    elif kind in ("guitar_fallback",):
        d.line([(cx - s*.25, cy + s*.3), (cx, cy - s*.3), (cx + s*.25, cy + s*.3)], fill=col, width=int(L*1.6))
    else:  # letter glyphs: simple letter-ish marks
        d.line([(cx - s*.25, cy + s*.3), (cx, cy - s*.3), (cx + s*.25, cy + s*.3)], fill=col, width=int(L*1.6))
        d.line([(cx - s*.14, cy + s*.08), (cx + s*.14, cy + s*.08)], fill=col, width=L)

def render(era, base, kind):
    N = SIZE * SS
    r = int(N * (0.22 if era != "glass27" else 0.30))
    mask = rmask(N, N, r)
    if era == "ios1":
        top, bot = shade(base, 1.25), shade(base, 0.62)
        im = vgrad(N, N, top, bot)
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, N-1, N-1), r, outline=(255, 255, 255, 60), width=SS*2)
        glyph_col, shadow = (255, 255, 255, 245), (0, 0, 0, 110)
        sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        glyph(ImageDraw.Draw(sh), kind, N/2, N/2 + SS*3, N*.62, shadow, SS)
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(SS*2)))
        glyph(ImageDraw.Draw(im), kind, N/2, N/2, N*.62, glyph_col, SS)
        # hard-edged gloss ellipse across the top half
        gl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(gl).ellipse((-N*.25, -N*.55, N*1.25, N*.52), fill=(255, 255, 255, 70))
        im = Image.alpha_composite(im, gl)
    elif era == "ios7":
        im = vgrad(N, N, shade(base, 1.12), shade(base, 0.92))
        glyph(ImageDraw.Draw(im), kind, N/2, N/2, N*.60, (255, 255, 255, 255), SS)
    else:  # glass27
        backdrop = vgrad(N, N, shade(base, 0.9), shade(base, 0.45))
        pane = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        pd = ImageDraw.Draw(pane)
        pd.rounded_rectangle((N*.04, N*.04, N*.96, N*.96), int(r*.9), fill=(255, 255, 255, 46), outline=(255, 255, 255, 140), width=SS*2)
        im = Image.alpha_composite(backdrop, pane)
        spec = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ImageDraw.Draw(spec).ellipse((N*.08, N*.02, N*.80, N*.40), fill=(255, 255, 255, 60))
        im = Image.alpha_composite(im, spec.filter(ImageFilter.GaussianBlur(SS*6)))
        sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        glyph(ImageDraw.Draw(sh), kind, N/2, N/2 + SS*2, N*.58, (0, 0, 0, 70), SS)
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(SS*3)))
        glyph(ImageDraw.Draw(im), kind, N/2, N/2, N*.58, (255, 255, 255, 235), SS)
    im.putalpha(mask)
    return im.resize((SIZE, SIZE), Image.LANCZOS)

def main():
    eras = sys.argv[1:] or ["ios1", "ios7", "glass27"]
    for era in eras:
        out = ROOT / era / "Icons"
        out.mkdir(parents=True, exist_ok=True)
        for bid, (label, base, kind) in APPS.items():
            render(era, base, kind).save(out / f"{bid}.png", optimize=True)
        print(f"{era}: {len(APPS)} icons -> {out}")

if __name__ == "__main__":
    main()
