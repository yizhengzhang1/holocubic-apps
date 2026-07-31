#!/usr/bin/env python3
"""Build optimized animated gallery GIFs from HoloCubic PNG captures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


TYPES = (
    "peony",
    "chrysanthemum",
    "willow",
    "strobe",
    "spinner",
    "multibreak",
    "rapidfire",
    "comet",
    "waterfall",
    "brocade_crown",
)
FRAME_COUNT = 16
FRAME_DURATION_MS = 180
GIF_COLORS = 64


def load_frames(frame_root: Path, firework_type: str) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for index in range(1, FRAME_COUNT + 1):
        path = frame_root / firework_type / f"{index:02d}.png"
        with Image.open(path) as source:
            frame = source.convert("RGB")
            if frame.size != (320, 240):
                raise ValueError(f"{path}: expected 320x240, got {frame.size}")
            frames.append(frame.copy())
    return frames


def shared_palette(frames: list[Image.Image]) -> Image.Image:
    palette_source = Image.new("RGB", (320, 240 * len(frames)))
    for index, frame in enumerate(frames):
        palette_source.paste(frame, (0, index * 240))
    return palette_source.quantize(
        colors=GIF_COLORS,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )


def encode_gif(frames: list[Image.Image], output_path: Path) -> None:
    palette = shared_palette(frames)
    indexed = [
        frame.quantize(palette=palette, dither=Image.Dither.NONE)
        for frame in frames
    ]
    indexed[0].save(
        output_path,
        format="GIF",
        save_all=True,
        append_images=indexed[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        disposal=1,
        optimize=True,
        interlace=False,
    )


def write_contact_sheet(
    frames: list[Image.Image], output_path: Path, sample_indexes: tuple[int, ...]
) -> None:
    thumb_size = (160, 120)
    sheet = Image.new("RGB", (thumb_size[0] * len(sample_indexes), 120), "black")
    for slot, frame_index in enumerate(sample_indexes):
        thumb = frames[frame_index].resize(thumb_size, Image.Resampling.LANCZOS)
        sheet.paste(thumb, (slot * thumb_size[0], 0))
    sheet.save(output_path, format="PNG", optimize=True)


def validate_gif(path: Path) -> dict[str, int]:
    if path.read_bytes()[:6] != b"GIF89a":
        raise ValueError(f"{path}: missing GIF89a header")
    with Image.open(path) as image:
        frame_count = image.n_frames
        loop = int(image.info.get("loop", -1))
        if image.size != (320, 240):
            raise ValueError(f"{path}: expected 320x240, got {image.size}")
        if frame_count < 8 or frame_count > FRAME_COUNT:
            raise ValueError(
                f"{path}: expected 8-{FRAME_COUNT} encoded frames, got {frame_count}"
            )
        if loop != 0:
            raise ValueError(f"{path}: expected infinite loop, got {loop}")
        durations = []
        for index in range(frame_count):
            image.seek(index)
            durations.append(int(image.info.get("duration", 0)))
        if any(duration <= 0 for duration in durations):
            raise ValueError(f"{path}: found zero-duration frame")
        expected_duration = FRAME_COUNT * FRAME_DURATION_MS
        if sum(durations) != expected_duration:
            raise ValueError(
                f"{path}: expected {expected_duration} ms, got {sum(durations)} ms"
            )
    return {
        "bytes": path.stat().st_size,
        "frames": frame_count,
        "source_frames": FRAME_COUNT,
        "duration_ms": sum(durations),
        "width": 320,
        "height": 240,
        "colors": GIF_COLORS,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("frame_root", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--types",
        nargs="+",
        choices=TYPES,
        default=list(TYPES),
        metavar="TYPE",
        help="firework types to build (default: all ten)",
    )
    args = parser.parse_args()
    selected_types = tuple(dict.fromkeys(args.types))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    if any(args.output_dir.iterdir()):
        raise SystemExit(f"output directory must be empty: {args.output_dir}")

    report: dict[str, dict[str, int]] = {}
    for firework_type in selected_types:
        frames = load_frames(args.frame_root, firework_type)
        gif_path = args.output_dir / f"fireworks-showcase-{firework_type}.gif"
        encode_gif(frames, gif_path)
        write_contact_sheet(
            frames,
            args.output_dir / f"qa-{firework_type}.png",
            (0, 3, 6, 9, 12, 15),
        )
        report[firework_type] = validate_gif(gif_path)
        print(
            f"{firework_type}: {report[firework_type]['bytes']} bytes, "
            f"{report[firework_type]['frames']} frames"
        )

    report["total"] = {
        "bytes": sum(item["bytes"] for item in report.values()),
        "frames": FRAME_COUNT * len(selected_types),
        "duration_ms": FRAME_DURATION_MS * FRAME_COUNT,
        "width": 320,
        "height": 240,
        "colors": GIF_COLORS,
        "types": len(selected_types),
    }
    (args.output_dir / "report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
