#!/usr/bin/env python3
"""Create the English player-facing story resource from its Chinese source.

The game ships only the generated JSON, so translating its display fields keeps
the original screenplay untouched and preserves all branch IDs and asset keys.
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]
STORY = ROOT / "GameTemplate" / "GameTemplate" / "Resources" / "StoryContent.json"
CACHE = ROOT / "Tools" / ".story_translation_cache.json"
CLUE_KEY_ALIASES = {
    "第五个杯子": "fifth cup",
    "第五只水杯": "fifth cup",
    "被擦掉的编剧署名": "The erased screenwriter's signature",
    "被刮去的名字": "scratched-out name",
    "蓝色玻璃发夹": "blue glass hairpin",
    "未冲洗的最后一张照片": "The last undeveloped photo",
}


def contains_han(value: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in value)


def fetch_translation(source: str) -> str:
    url = (
        "https://translate.googleapis.com/translate_a/single?client=gtx"
        "&sl=zh-CN&tl=en&dt=t&q=" + quote(source)
    )
    result = subprocess.run(
        ["curl", "-L", "--retry", "3", "--max-time", "30", "-sS", url],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(result.stdout)
    return "".join(part[0] for part in payload[0]).strip()


def fetch_batch(sources: list[str]) -> list[str]:
    delimiter = "\n[[[STORY_SEGMENT]]]\n"
    translated = fetch_translation(delimiter.join(sources))
    parts = [part.strip() for part in translated.split("[[[STORY_SEGMENT]]]")]
    if len(parts) != len(sources):
        raise RuntimeError("The translation response lost a story segment boundary.")
    return parts


def main() -> int:
    story = json.loads(STORY.read_text())
    cache = json.loads(CACHE.read_text()) if CACHE.exists() else {}
    fields = ("chapter", "scene", "speaker", "text")
    pending = []
    for node in story["nodes"].values():
        for key in fields:
            value = node.get(key)
            if isinstance(value, str) and contains_han(value) and value not in pending:
                pending.append(value)
    for chapter in story.get("chapters", []):
        value = chapter.get("title")
        if isinstance(value, str) and contains_han(value) and value not in pending:
            pending.append(value)
    for clue in story.get("hiddenEnding", {}).get("requiredClues", []):
        if isinstance(clue, str) and contains_han(clue) and clue not in pending:
            pending.append(clue)
    for node in story["nodes"].values():
        for effect in node.get("effects", []):
            value = effect.get("key")
            if isinstance(value, str) and contains_han(value) and value not in pending:
                pending.append(value)
        for option in node.get("options", []):
            value = option.get("text")
            if isinstance(value, str) and contains_han(value) and value not in pending:
                pending.append(value)
            for effect in option.get("effects", []):
                value = effect.get("key")
                if isinstance(value, str) and contains_han(value) and value not in CLUE_KEY_ALIASES and value not in pending:
                    pending.append(value)

    untranslated = [source for source in pending if source not in cache]
    batches: list[list[str]] = []
    batch: list[str] = []
    batch_length = 0
    for source in untranslated:
        # Keep the URL comfortably below proxy limits after percent encoding.
        if batch and batch_length + len(source) > 1100:
            batches.append(batch)
            batch, batch_length = [], 0
        batch.append(source)
        batch_length += len(source)
    if batch:
        batches.append(batch)
    for index, batch in enumerate(batches, start=1):
        for source, translation in zip(batch, fetch_batch(batch)):
            cache[source] = translation
        CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + "\n")
        print(f"Translated batch {index}/{len(batches)} ({len(batch)} segments)", file=sys.stderr)
        time.sleep(0.15)

    for node in story["nodes"].values():
        for key in fields:
            value = node.get(key)
            if isinstance(value, str) and value in cache:
                node[key] = cache[value]
        for option in node.get("options", []):
            value = option.get("text")
            if isinstance(value, str) and value in cache:
                option["text"] = cache[value]
            for effect in option.get("effects", []):
                effect["key"] = CLUE_KEY_ALIASES.get(effect.get("key"), cache.get(effect.get("key"), effect.get("key")))

    # These metadata values are surfaced by the memory tree and hidden-ending
    # state.  Keep their localized labels in sync with the playable content.
    for chapter in story.get("chapters", []):
        if chapter.get("title") in cache:
            chapter["title"] = cache[chapter["title"]]
    hidden_ending = story.get("hiddenEnding", {})
    hidden_ending["requiredClues"] = [cache.get(clue, clue) for clue in hidden_ending.get("requiredClues", [])]
    for node in story["nodes"].values():
        for effect in node.get("effects", []):
            effect["key"] = CLUE_KEY_ALIASES.get(effect.get("key"), cache.get(effect.get("key"), effect.get("key")))

    # Older cached batches used one bracket too few when splitting the marker.
    # Remove that artifact once, while retaining legitimate inline punctuation.
    def normalize(value: str) -> str:
        return value[2:] if value.startswith("]\n") else value
    for node in story["nodes"].values():
        for key in fields:
            if isinstance(node.get(key), str):
                node[key] = normalize(node[key])
        for option in node.get("options", []):
            if isinstance(option.get("text"), str):
                option["text"] = normalize(option["text"])

    story["source"] = "English localization adapted from the approved screenplay"
    STORY.write_text(json.dumps(story, ensure_ascii=False, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
