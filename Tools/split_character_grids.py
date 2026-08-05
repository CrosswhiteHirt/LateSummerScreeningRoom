#!/usr/bin/env python3
"""Split 3×3 character sheets and remove their connected white backgrounds.

The source sheets are 1254×1254 with eight filled cells and one blank cell.
Original files are never modified.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path
import sys
import tempfile

import numpy as np
from PIL import Image, ImageFilter


SOURCE_DIR = Path("material/人物静态神态动作")
OUTPUT_DIR = SOURCE_DIR / "已分割透明"
GRID_SIZE = 3
CELL_SIZE = 418
INSET = 4
PADDING = 6
GRABCUT_TOOL_DIR = Path("/Users/edy/Downloads/pan/tool/cv_tool")

VARIANTS = {
    "神态": ["中性", "开心", "惊讶", "疑惑", "担心", "难过", "生气", "思考"],
    "动作": ["中性", "挥手", "指向", "观察", "对话", "拿道具", "奔跑", "庆祝"],
}


def trim_transparent_padding(image: Image.Image) -> Image.Image:
    alpha = np.asarray(image.getchannel("A"))
    occupied_y, occupied_x = np.where(alpha > 8)
    if not len(occupied_x):
        return image
    left = max(0, int(occupied_x.min()) - PADDING)
    top = max(0, int(occupied_y.min()) - PADDING)
    right = min(image.width, int(occupied_x.max()) + PADDING + 1)
    bottom = min(image.height, int(occupied_y.max()) + PADDING + 1)
    return image.crop((left, top, right, bottom))


def soften_outer_contour(image: Image.Image) -> Image.Image:
    """Anti-alias only into exterior transparent pixels, never into the subject."""
    alpha = np.asarray(image.getchannel("A"), dtype=np.uint8)
    height, width = alpha.shape
    transparent = alpha <= 8
    exterior = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()
    for x in range(width):
        for y in (0, height - 1):
            if transparent[y, x] and not exterior[y, x]:
                exterior[y, x] = True
                queue.append((y, x))
    for y in range(height):
        for x in (0, width - 1):
            if transparent[y, x] and not exterior[y, x]:
                exterior[y, x] = True
                queue.append((y, x))
    while queue:
        y, x = queue.popleft()
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= next_y < height and 0 <= next_x < width and transparent[next_y, next_x] and not exterior[next_y, next_x]:
                exterior[next_y, next_x] = True
                queue.append((next_y, next_x))

    blurred = np.asarray(image.getchannel("A").filter(ImageFilter.GaussianBlur(1.2)), dtype=np.uint8)
    softened = alpha.copy()
    softened[exterior] = np.maximum(softened[exterior], blurred[exterior])
    result = image.copy()
    result.putalpha(Image.fromarray(softened, "L"))
    return result


def source_kind(path: Path) -> str:
    for kind in VARIANTS:
        if path.stem.endswith(kind):
            return kind
    raise ValueError(f"Unrecognized sheet type: {path.name}")


def find_grid_lines(image: Image.Image, axis: int) -> list[int]:
    """Locate the four actual grid borders; AI sheets are not always evenly spaced."""
    rgb = np.asarray(image.convert("RGB"))
    channel_range = rgb.max(axis=2).astype(np.int16) - rgb.min(axis=2).astype(np.int16)
    brightness = rgb.mean(axis=2)
    line_like = (channel_range <= 28) & (brightness <= 245)
    profile = line_like.mean(axis=axis)
    length = image.height if axis == 1 else image.width
    strong_positions = np.flatnonzero(profile >= 0.8)
    groups: list[np.ndarray] = []
    if len(strong_positions):
        start = 0
        for index in range(1, len(strong_positions) + 1):
            if index == len(strong_positions) or strong_positions[index] > strong_positions[index - 1] + 5:
                groups.append(strong_positions[start:index])
                start = index
    expected = [round(length * index / GRID_SIZE) for index in range(GRID_SIZE + 1)]
    boundaries = [int(group[np.argmax(profile[group])]) for group in groups]
    selected: list[int] = []
    for index, center in enumerate(expected):
        nearby = [position for position in boundaries if abs(position - center) <= 150]
        if nearby:
            selected.append(min(nearby, key=lambda position: abs(position - center)))
            continue
        # Fallback for unusually faint grid lines.
        start = max(0, center - 40)
        end = min(length, center + 41)
        selected.append(int(start + np.argmax(profile[start:end])))
    return selected


def main() -> None:
    sys.path.insert(0, str(GRABCUT_TOOL_DIR))
    from remove_bg import remove_white_background
    from remove_bg_grabcut import grabcut_remove_bg

    source_files = sorted(
        path for path in SOURCE_DIR.glob("*.png")
        if not path.name.startswith("已移除背景的")
    )
    if not source_files:
        raise FileNotFoundError(f"No PNG sheets found in {SOURCE_DIR}")

    generated = 0
    with tempfile.TemporaryDirectory(prefix="pangame-character-split-") as temporary_directory:
        temporary_dir = Path(temporary_directory)
        for source in source_files:
            kind = source_kind(source)
            character = source.stem[: -len(kind)].strip()
            variants = VARIANTS[kind]
            image = Image.open(source).convert("RGBA")
            if image.size != (CELL_SIZE * GRID_SIZE, CELL_SIZE * GRID_SIZE):
                raise ValueError(f"Unexpected image size for {source.name}: {image.size}")

            vertical_lines = find_grid_lines(image, axis=0)
            horizontal_lines = find_grid_lines(image, axis=1)
            target_dir = OUTPUT_DIR / kind
            target_dir.mkdir(parents=True, exist_ok=True)
            for index, variant in enumerate(variants):
                row, column = divmod(index, GRID_SIZE)
                left = vertical_lines[column] + INSET
                top = horizontal_lines[row] + INSET
                right = vertical_lines[column + 1] - INSET
                bottom = horizontal_lines[row + 1] - INSET
                cell = image.crop((left, top, right, bottom))
                raw_input = temporary_dir / f"raw-{generated}.png"
                masked_output = temporary_dir / f"masked-{generated}.png"
                cell.save(raw_input, "PNG")
                try:
                    grabcut_remove_bg(
                        str(raw_input), str(masked_output), iterations=12, edge_margin=1,
                        feather=0, shrink_mask=0, white_thresh_s=30, white_thresh_v=235,
                        close_size=10, min_hole_area=1, edge_protect=1,
                    )
                except Exception:
                    remove_white_background(str(raw_input), str(masked_output), threshold=250, edge_feather=0)
                cutout = trim_transparent_padding(Image.open(masked_output).convert("RGBA"))
                if cutout.getchannel("A").getbbox() is None:
                    # GrabCut's enclosed-hole pass can fail on very pale, small
                    # anime characters. Recover the source pixels with a strict
                    # edge-connected canvas mask instead of leaving a blank asset.
                    remove_white_background(str(raw_input), str(masked_output), threshold=250, edge_feather=0)
                    cutout = trim_transparent_padding(Image.open(masked_output).convert("RGBA"))
                cutout = soften_outer_contour(cutout)
                cutout = trim_transparent_padding(cutout)
                output = target_dir / f"{character}_{kind}_{variant}.png"
                cutout.save(output, "PNG")
                generated += 1

    print(f"Generated {generated} transparent character images in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
