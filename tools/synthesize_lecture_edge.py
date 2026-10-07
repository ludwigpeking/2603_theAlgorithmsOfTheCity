"""
Synthesize speaker notes from Lecture_10min_AlgorithmsOfCities.md
into Lecture_speech.mp3 using Microsoft's free Edge TTS endpoint.

Voice: en-US-AndrewMultilingualNeural (male, mature, conversational/academic)
"""

from __future__ import annotations

import asyncio
import re
from pathlib import Path

import edge_tts

ROOT = Path(__file__).resolve().parents[1]
LECTURE = ROOT / "Lecture_10min_AlgorithmsOfCities.md"
OUTPUT = ROOT / "Lecture_speech.mp3"

VOICE = "en-US-AndrewMultilingualNeural"
RATE = "-8%"          # academic deliberateness


def extract_notes(md: str) -> list[str]:
    pattern = re.compile(
        r"^>\s*\*\*Speaker note[^*]*\*\*\s*:?\s*(.+?)(?=\r?\n(?!>)|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    return [m.group(1) for m in pattern.finditer(md)]


def clean(text: str) -> str:
    text = re.sub(r"^>\s?", "", text, flags=re.MULTILINE)
    text = text.replace("**", "")
    text = re.sub(r"(?<!\*)\*(?!\*)", "", text)
    text = text.replace("`", "")
    text = text.replace("$", "")
    text = re.sub(r"\\([A-Za-z]+)", r"\1", text)   # \sigma -> sigma
    text = re.sub(r"\s+", " ", text).strip()
    return text


async def main() -> None:
    md = LECTURE.read_text(encoding="utf-8")
    notes = [clean(n) for n in extract_notes(md)]
    if not notes:
        raise SystemExit("No speaker notes found.")
    print(f"Extracted {len(notes)} speaker notes.")

    # Paragraph breaks between slides give Edge TTS natural pauses.
    payload = "\n\n".join(notes)
    print(f"Payload: {len(payload)} chars (~{len(payload)//900} min of speech).")

    communicate = edge_tts.Communicate(payload, voice=VOICE, rate=RATE)
    await communicate.save(str(OUTPUT))

    size_mb = OUTPUT.stat().st_size / (1024 * 1024)
    print(f"Wrote {OUTPUT} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    asyncio.run(main())
