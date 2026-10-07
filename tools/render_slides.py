"""
Render each slide of Lecture_10min_AlgorithmsOfCities.md to a PNG image.

- Strips the "Slide N — " (and "Closing — ") prefix from each title.
- Strips the speaker-note blockquote.
- Renders to a 1920x1080 light-themed HTML page; uses MathJax for math.
- Screenshots via Microsoft Edge in headless mode.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
LECTURE = ROOT / "Lecture_10min_AlgorithmsOfCities.md"
SLIDES_DIR = ROOT / "slides"
SLIDES_DIR.mkdir(exist_ok=True)

EDGE_CANDIDATES = [
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]
EDGE = next((str(p) for p in EDGE_CANDIDATES if p.exists()), None)
if EDGE is None:
    raise SystemExit("Microsoft Edge not found.")


# --- Parsing ----------------------------------------------------------------

def parse_slides(md_text: str) -> list[tuple[str, str]]:
    sections = re.split(r"(?m)^---\s*$", md_text)
    slides: list[tuple[str, str]] = []
    for sec in sections:
        sec = sec.strip()
        if not sec.startswith("## "):
            continue
        first, _, rest = sec.partition("\n")
        title = re.sub(r"^##\s+", "", first).strip()
        title = re.sub(r"^(Slide\s+\d+|Closing)\s*[—–\-]\s*", "", title).strip()
        body = "\n".join(
            line for line in rest.splitlines()
            if not line.lstrip().startswith("> **Speaker note")
        ).strip()
        slides.append((title, body))
    return slides


# --- Markdown -> HTML (with math protection) --------------------------------

def normalize_lists(text: str) -> str:
    """Ensure a blank line precedes any list block so Python-Markdown sees it."""
    lines = text.split("\n")
    out: list[str] = []
    list_re = re.compile(r"^\s*([-*+]|\d+\.)\s")
    for i, line in enumerate(lines):
        if i > 0 and list_re.match(line):
            prev = lines[i - 1]
            if prev.strip() and not list_re.match(prev):
                out.append("")
        out.append(line)
    return "\n".join(out)


def md_to_html(body: str) -> str:
    math_blocks: list[str] = []

    def stash(match: re.Match) -> str:
        math_blocks.append(match.group(0))
        return f"@@MATH{len(math_blocks) - 1}@@"

    body = re.sub(r"\$\$.+?\$\$", stash, body, flags=re.DOTALL)
    body = re.sub(r"\$[^\$\n]+?\$", stash, body)
    body = normalize_lists(body)

    html = markdown.markdown(body, extensions=["extra", "sane_lists"])

    for i, m in enumerate(math_blocks):
        html = html.replace(f"@@MATH{i}@@", m)
    return html


def render_inline_md(text: str) -> str:
    """Render a single line of inline markdown (bold/italic) to HTML."""
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)\*(?!\*)", r"<em>\1</em>", text)
    return text


# --- HTML template ----------------------------------------------------------

CSS = """
:root {
  --ink: #1a1a1a;
  --ink-soft: #444;
  --rule: #b0b0b0;
  --accent: #1f4f8b;
  --paper: #ffffff;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  width: 1920px;
  height: 1080px;
  background: var(--paper);
  color: var(--ink);
  font-family: 'Cambria', 'Georgia', 'Times New Roman', serif;
  font-size: 26px;
  line-height: 1.45;
  padding: 70px 120px 55px 120px;
  display: flex;
  flex-direction: column;
}
h1 {
  font-family: 'Helvetica Neue', 'Segoe UI', Arial, sans-serif;
  font-weight: 600;
  font-size: 46px;
  letter-spacing: -0.01em;
  color: #111;
  margin: 0 0 22px 0;
  padding-bottom: 18px;
  border-bottom: 2px solid var(--rule);
}
.content {
  flex: 1;
  overflow: hidden;
}
.content > p,
.content > ul,
.content > ol,
.content > div {
  margin: 10px 0;
}
strong { color: #000; }
em { color: var(--ink-soft); font-style: italic; }
ul, ol { padding-left: 32px; }
li { margin: 6px 0; }
li::marker { color: #888; }
mjx-container[display="true"] {
  margin: 16px auto !important;
}
.footer {
  margin-top: auto;
  font-family: 'Helvetica Neue', 'Segoe UI', Arial, sans-serif;
  font-size: 18px;
  color: #999;
  text-align: right;
  padding-top: 18px;
  border-top: 1px solid #e6e6e6;
}
.footer .accent { color: var(--accent); }
"""

HTML_TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8">
<style>{css}</style>
<script>
function autoFit() {{
  const c = document.querySelector('.content');
  if (!c) return;
  let zoom = 1.0, attempts = 0;
  while (c.scrollHeight > c.clientHeight + 1 && zoom > 0.55 && attempts < 40) {{
    zoom -= 0.03;
    c.style.zoom = zoom.toFixed(3);
    attempts++;
  }}
}}
window.MathJax = {{
  tex: {{
    inlineMath: [['$', '$']],
    displayMath: [['$$', '$$']],
    processEscapes: true,
  }},
  svg: {{ fontCache: 'global' }},
  startup: {{
    pageReady() {{
      return MathJax.startup.defaultPageReady().then(() => {{
        autoFit();
        document.title = 'READY';
      }});
    }}
  }}
}};
</script>
<script src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
</head><body>
<h1>{title}</h1>
<div class="content">{body}</div>
<div class="footer">The Algorithms of Cities &nbsp;<span class="accent">{slide_no:02d}</span></div>
</body></html>
"""


# --- Render -----------------------------------------------------------------

def render(slides: list[tuple[str, str]]) -> None:
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        for i, (title, body) in enumerate(slides, start=1):
            body_html = md_to_html(body)
            html = HTML_TEMPLATE.format(
                css=CSS,
                title=render_inline_md(title),
                body=body_html,
                slide_no=i,
            )
            html_path = td_path / f"slide_{i:02d}.html"
            png_path = SLIDES_DIR / f"slide_{i:02d}.png"
            html_path.write_text(html, encoding="utf-8")

            url = "file:///" + str(html_path).replace("\\", "/")
            cmd = [
                EDGE,
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                "--no-sandbox",
                f"--window-size=1920,1080",
                f"--virtual-time-budget=10000",
                f"--screenshot={png_path}",
                url,
            ]
            print(f"[{i:02d}] {title!r} -> {png_path.name}")
            subprocess.run(cmd, check=True, capture_output=True)
            if not png_path.exists():
                raise SystemExit(f"Failed: {png_path}")
        print(f"\nWrote {len(slides)} PNGs to {SLIDES_DIR}")


def main() -> None:
    md = LECTURE.read_text(encoding="utf-8")
    slides = parse_slides(md)
    if not slides:
        raise SystemExit("No slides found.")
    print(f"Parsed {len(slides)} slides.")
    render(slides)


if __name__ == "__main__":
    main()
