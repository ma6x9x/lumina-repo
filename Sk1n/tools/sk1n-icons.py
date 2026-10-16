#!/usr/bin/env python3
"""Generate ORIGINAL placeholder era-styled icons for stock bundle IDs.

Every pixel is drawn here with PIL primitives (rounded rectangles, gradients,
simple geometric glyphs). NO Apple artwork is used, copied, traced or
redistributed. The glyphs are deliberately abstract stand-ins; skin authors are
expected to replace them with their own art.

    pip install pillow
    python3 tools/sk1n-icons.py            # writes all three skins
    python3 tools/sk1n-icons.py ios7       # one skin
"""
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

def glyph(d, kind, cx, cy, s, col, w):
    """Abstract, original geometric glyphs on a (cx,cy) centre, scale s."""
    L = max(2, int(s * 0.09))
    if kind in ("phone",):
        d.arc((cx - s*.35, cy - s*.35, cx + s*.35, cy + s*.35), 200, 340, fill=col, width=int(L*2.2))
    elif kind in ("bubble",):
        d.ellipse((cx - s*.42, cy - s*.34, cx + s*.42, cy + s*.30), fill=col)
        d.polygon([(cx - s*.25, cy + s*.2), (cx - s*.40, cy + s*.42), (cx - s*.05, cy + s*.27)], fill=col)
    elif kind in ("envelope",):
        d.rounded_rectangle((cx - s*.42, cy - s*.28, cx + s*.42, cy + s*.28), int(s*.06), outline=col, width=L)
        d.line([(cx - s*.42, cy - s*.26), (cx, cy + s*.06), (cx + s*.42, cy - s*.26)], fill=col, width=L)
    elif kind in ("compass",):
        d.ellipse((cx - s*.42, cy - s*.42, cx + s*.42, cy + s*.42), outline=col, width=L)
        d.polygon([(cx + s*.22, cy - s*.22), (cx + s*.05, cy + s*.05), (cx - s*.22, cy + s*.22), (cx - s*.05, cy - s*.05)], fill=col)
    elif kind in ("note",):
        d.ellipse((cx - s*.30, cy + s*.10, cx - s*.06, cy + s*.34), fill=col)
        d.rectangle((cx - s*.09, cy - s*.34, cx - s*.04, cy + s*.22), fill=col)
        d.polygon([(cx - s*.05, cy - s*.34), (cx + s*.30, cy - s*.22), (cx + s*.30, cy - s*.10), (cx - s*.05, cy - s*.20)], fill=col)
    elif kind in ("camera",):
        d.rounded_rectangle((cx - s*.42, cy - s*.24, cx + s*.42, cy + s*.30), int(s*.08), outline=col, width=L)
        d.ellipse((cx - s*.17, cy - s*.12, cx + s*.17, cy + s*.22), outline=col, width=L)
    elif kind in ("flower",):
        for i in range(8):
            import math
            a = i * math.pi / 4
            x, y = cx + math.cos(a) * s*.22, cy + math.sin(a) * s*.22
            d.ellipse((x - s*.14, y - s*.14, x + s*.14, y + s*.14), fill=col)
    elif kind in ("gear",):
        import math
        for i in range(8):
            a = i * math.pi / 4
            x, y = cx + math.cos(a) * s*.36, cy + math.sin(a) * s*.36
            d.ellipse((x - s*.08, y - s*.08, x + s*.08, y + s*.08), fill=col)
        d.ellipse((cx - s*.30, cy - s*.30, cx + s*.30, cy + s*.30), outline=col, width=int(L*2))
    elif kind in ("grid",):
        for i in (-1, 0, 1):
            for j in (-1, 0, 1):
                d.rectangle((cx + i*s*.28 - s*.08, cy + j*s*.28 - s*.08, cx + i*s*.28 + s*.08, cy + j*s*.28 + s*.08), fill=col)
    elif kind in ("clock",):
        d.ellipse((cx - s*.42, cy - s*.42, cx + s*.42, cy + s*.42), outline=col, width=L)
        d.line([(cx, cy), (cx, cy - s*.28)], fill=col, width=L)
        d.line([(cx, cy), (cx + s*.20, cy + s*.08)], fill=col, width=L)
    elif kind in ("pin",):
        d.ellipse((cx - s*.26, cy - s*.40, cx + s*.26, cy + s*.12), fill=col)
        d.polygon([(cx - s*.20, cy), (cx + s*.20, cy), (cx, cy + s*.42)], fill=col)
    elif kind in ("sun",):
        import math
        d.ellipse((cx - s*.20, cy - s*.20, cx + s*.20, cy + s*.20), fill=col)
        for i in range(8):
            a = i * math.pi / 4
            d.line([(cx + math.cos(a)*s*.30, cy + math.sin(a)*s*.30), (cx + math.cos(a)*s*.44, cy + math.sin(a)*s*.44)], fill=col, width=L)
    elif kind in ("lines",):
        for k in (-1, 0, 1):
            d.line([(cx - s*.36, cy + k*s*.24), (cx + s*.36, cy + k*s*.24)], fill=col, width=L)
    elif kind in ("check",):
        d.line([(cx - s*.30, cy), (cx - s*.08, cy + s*.24), (cx + s*.32, cy - s*.26)], fill=col, width=int(L*1.6))
    elif kind in ("plusminus",):
        d.line([(cx - s*.30, cy - s*.18), (cx + s*.30, cy - s*.18)], fill=col, width=L)
        d.line([(cx, cy - s*.40), (cx, cy + s*.04)], fill=col, width=L)
        d.line([(cx - s*.30, cy + s*.30), (cx + s*.30, cy + s*.30)], fill=col, width=L)
    elif kind in ("heart",):
        d.ellipse((cx - s*.38, cy - s*.34, cx + .0, cy + s*.06), fill=col)
        d.ellipse((cx, cy - s*.34, cx + s*.38, cy + s*.06), fill=col)
        d.polygon([(cx - s*.36, cy - s*.04), (cx + s*.36, cy - s*.04), (cx, cy + s*.40)], fill=col)
    elif kind in ("card",):
        d.rounded_rectangle((cx - s*.42, cy - s*.28, cx + s*.42, cy + s*.28), int(s*.06), outline=col, width=L)
        d.line([(cx - s*.42, cy - s*.08), (cx + s*.42, cy - s*.08)], fill=col, width=L)
    elif kind in ("chart",):
        d.line([(cx - s*.4, cy + s*.2), (cx - s*.1, cy - s*.05), (cx + s*.1, cy + s*.1), (cx + s*.4, cy - s*.3)], fill=col, width=L)
    elif kind in ("video",):
        d.rounded_rectangle((cx - s*.42, cy - s*.22, cx + s*.12, cy + s*.22), int(s*.06), fill=col)
        d.polygon([(cx + s*.18, cy), (cx + s*.42, cy - s*.18), (cx + s*.42, cy + s*.18)], fill=col)
    elif kind in ("wave",):
        for i, hh in enumerate((.1, .25, .4, .25, .1, .3, .15)):
            x = cx - s*.36 + i*s*.12
            d.line([(x, cy - s*hh), (x, cy + s*hh)], fill=col, width=L)
    elif kind in ("house",):
        d.polygon([(cx - s*.42, cy), (cx, cy - s*.40), (cx + s*.42, cy)], fill=col)
        d.rectangle((cx - s*.30, cy, cx + s*.30, cy + s*.34), fill=col)
    else:  # letter glyphs: a, n, guitar -> simple letter-ish marks
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
