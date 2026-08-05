#!/usr/bin/env python3
"""Split system background-removed 3×3 character sheets without altering alpha."""

from pathlib import Path

from PIL import Image


SOURCE_DIR = Path("material/人物静态神态动作")
OUTPUT_DIR = SOURCE_DIR / "已分割透明"
CELL_SIZE = 418
PADDING = 6
VARIANTS = {
    "神态": ["中性", "开心", "惊讶", "疑惑", "担心", "难过", "生气", "思考"],
    "动作": ["中性", "挥手", "指向", "观察", "对话", "拿道具", "奔跑", "庆祝"],
}


def trim_transparent_padding(image: Image.Image) -> Image.Image:
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        return image
    left, top, right, bottom = bounds
    return image.crop((
        max(0, left - PADDING), max(0, top - PADDING),
        min(image.width, right + PADDING), min(image.height, bottom + PADDING),
    ))


def main() -> None:
    source_files = sorted(SOURCE_DIR.glob("已移除背景的*.png"))
    if not source_files:
        raise FileNotFoundError("No system background-removed sheets found")

    generated = 0
    for source in source_files:
        kind = next(kind for kind in VARIANTS if source.stem.endswith(kind))
        character = source.stem.removeprefix("已移除背景的").removesuffix(kind).strip()
        image = Image.open(source).convert("RGBA")
        if image.size != (CELL_SIZE * 3, CELL_SIZE * 3):
            raise ValueError(f"Unexpected sheet size: {source.name} — {image.size}")
        target_dir = OUTPUT_DIR / kind
        target_dir.mkdir(parents=True, exist_ok=True)
        for index, variant in enumerate(VARIANTS[kind]):
            row, column = divmod(index, 3)
            cell = image.crop((
                column * CELL_SIZE,
                row * CELL_SIZE,
                (column + 1) * CELL_SIZE,
                (row + 1) * CELL_SIZE,
            ))
            output = target_dir / f"{character}_{kind}_{variant}.png"
            trim_transparent_padding(cell).save(output, "PNG")
            generated += 1
    print(f"Generated {generated} unmodified-alpha character images in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
