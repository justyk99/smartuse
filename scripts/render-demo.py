#!/usr/bin/env python3
"""render-demo.py — render a terminal-replay GIF from a scene file of REAL captured output. No model, no network.

Scene file format (plain text):
  $ <command>          a shell prompt line, typed character by character
  > <text>             a Claude Code prompt line, typed the same way
  <any other line>     output, revealed line by line
  @pause <seconds>     hold the current frame
  @clear               clear the screen
Lines are drawn verbatim; a line longer than --cols wraps. The point is honesty: paste what the tool printed, not a mock-up.

usage: python3 scripts/render-demo.py <scene.txt> <out.gif> [--cols 100] [--rows 30] [--font-size 15]
"""
import argparse, pathlib
from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"]
BG, FG, DIM, ACCENT, PROMPT = (24, 24, 28), (230, 230, 225), (140, 140, 135), (120, 200, 160), (255, 200, 90)


def load_font(size):
    for f in FONT_CANDIDATES:
        if pathlib.Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


class Term:
    def __init__(self, cols, rows, font_size):
        self.cols, self.rows = cols, rows
        self.font = load_font(font_size)
        bbox = self.font.getbbox("M")
        self.cw, self.ch = bbox[2] - bbox[0], int(font_size * 1.45)
        self.pad = 18
        self.w, self.h = self.cols * self.cw + 2 * self.pad, self.rows * self.ch + 2 * self.pad
        self.lines = []
        self.frames, self.durations = [], []

    def color(self, line):
        if line.startswith(("$ ", "> ")):
            return PROMPT
        if line.startswith(("|", "+--", "steps ", "receipts:", "ledger:")):
            return ACCENT if line.startswith(("receipts:", "steps ", "ledger:")) else FG
        if line.startswith(("#", "//", "PASS", "✓")):
            return DIM
        return FG

    def snap(self, dur):
        img = Image.new("RGB", (self.w, self.h), BG)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle((0, 0, self.w, self.h), radius=12, fill=BG)
        for i, (dot) in enumerate(((255, 95, 86), (255, 189, 46), (39, 201, 63))):
            d.ellipse((self.pad + i * 18, 6, self.pad + i * 18 + 10, 16), fill=dot)
        rows = []
        for line in self.lines:
            chunks = [line[i:i + self.cols] for i in range(0, max(len(line), 1), self.cols)]
            rows += [(c, self.color(line)) for c in chunks]
        for i, (text, col) in enumerate(rows[-self.rows:]):
            d.text((self.pad, self.pad + 6 + i * self.ch), text, font=self.font, fill=col)
        self.frames.append(img.quantize(colors=64, method=Image.Quantize.MEDIANCUT))
        self.durations.append(int(dur * 1000))

    def type_line(self, text, cps=28):
        self.lines.append("")
        step = max(1, int(cps / 10))
        for i in range(0, len(text) + 1, step):
            self.lines[-1] = text[:i] + "▌"
            self.snap(0.1)
        self.lines[-1] = text
        self.snap(0.35)

    def out_line(self, text, dur=0.12):
        self.lines.append(text)
        self.snap(dur)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene"); ap.add_argument("out")
    ap.add_argument("--cols", type=int, default=100); ap.add_argument("--rows", type=int, default=30); ap.add_argument("--font-size", type=int, default=15)
    a = ap.parse_args()
    t = Term(a.cols, a.rows, a.font_size)
    for raw in pathlib.Path(a.scene).read_text(encoding="utf-8").splitlines():
        if raw.startswith("@pause"):
            t.snap(float(raw.split()[1]) if len(raw.split()) > 1 else 1.0)
        elif raw.startswith("@clear"):
            t.lines = []; t.snap(0.2)
        elif raw.startswith(("$ ", "> ")):
            t.type_line(raw, cps=60 if len(raw) > 60 else 28)
        else:
            t.out_line(raw)
    t.snap(3.0)
    t.frames[0].save(a.out, save_all=True, append_images=t.frames[1:], duration=t.durations, loop=0, optimize=True)
    total = sum(t.durations) / 1000
    print(f"wrote {a.out}: {len(t.frames)} frames, {total:.1f} s, {pathlib.Path(a.out).stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
