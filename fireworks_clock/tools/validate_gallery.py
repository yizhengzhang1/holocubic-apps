#!/usr/bin/env python3
"""Validate the Fireworks Clock animated gallery and its HTML references."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image


RECORDED_TYPES = (
    "peony",
    "chrysanthemum",
    "willow",
    "spinner",
    "strobe",
    "rapidfire",
    "multibreak",
    "comet",
    "waterfall",
    "brocade_crown",
)
TOTAL_CARD_COUNT = 10
PENDING_PREVIEW_COUNT = 0
EXPECTED_SIZE = (320, 240)
EXPECTED_DURATION_MS = 2880


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package_dir", type=Path)
    args = parser.parse_args()

    package_dir = args.package_dir.resolve()
    gallery_dir = package_dir / "assets" / "gallery"
    html = (package_dir / "info.html").read_text(encoding="utf-8")
    expected_names = {
        f"fireworks-showcase-{firework_type}.gif"
        for firework_type in RECORDED_TYPES
    }
    actual_names = {path.name for path in gallery_dir.glob("*.gif")}

    if actual_names != expected_names:
        raise ValueError(
            f"gallery files differ: missing={sorted(expected_names - actual_names)}, "
            f"extra={sorted(actual_names - expected_names)}"
        )
    if html.count('class="firework-card"') != TOTAL_CARD_COUNT:
        raise ValueError(
            f"HTML must contain exactly {TOTAL_CARD_COUNT} firework cards"
        )
    if html.count("data-local-src=") != len(RECORDED_TYPES):
        raise ValueError(
            f"HTML must contain exactly {len(RECORDED_TYPES)} local GIF sources"
        )
    if html.count("data-device-src=") != len(RECORDED_TYPES):
        raise ValueError(
            f"HTML must contain exactly {len(RECORDED_TYPES)} device GIF sources"
        )
    if html.count('class="firework-placeholder"') != PENDING_PREVIEW_COUNT:
        raise ValueError(
            f"HTML must contain exactly {PENDING_PREVIEW_COUNT} paused previews"
        )
    if re.search(r"fireworks-showcase-[^\"']+\.png", html):
        raise ValueError("HTML still references a PNG gallery asset")

    report: dict[str, dict[str, int]] = {}
    for name in sorted(expected_names):
        path = gallery_dir / name
        if path.read_bytes()[:6] != b"GIF89a":
            raise ValueError(f"{path}: missing GIF89a header")
        with Image.open(path) as image:
            if image.size != EXPECTED_SIZE:
                raise ValueError(f"{path}: expected {EXPECTED_SIZE}, got {image.size}")
            if not 8 <= image.n_frames <= 16:
                raise ValueError(f"{path}: invalid frame count {image.n_frames}")
            if int(image.info.get("loop", -1)) != 0:
                raise ValueError(f"{path}: animation must loop forever")
            durations: list[int] = []
            for index in range(image.n_frames):
                image.seek(index)
                durations.append(int(image.info.get("duration", 0)))
            if any(duration <= 0 for duration in durations):
                raise ValueError(f"{path}: found a zero-duration frame")
            if sum(durations) != EXPECTED_DURATION_MS:
                raise ValueError(
                    f"{path}: expected {EXPECTED_DURATION_MS} ms, "
                    f"got {sum(durations)} ms"
                )
        report[name] = {
            "bytes": path.stat().st_size,
            "frames": len(durations),
            "duration_ms": sum(durations),
        }

    print(json.dumps(report, ensure_ascii=False, indent=2))
    print("HTML/GIF gallery validation: OK")


if __name__ == "__main__":
    main()
