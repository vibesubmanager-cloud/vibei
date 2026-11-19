"""Precision/recall per class + notes for on-device latency testing."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--predictions", type=str, required=True, help="JSON list of preds")
    p.add_argument("--ground_truth", type=str, required=True, help="JSON list of GT")
    p.add_argument("--iou", type=float, default=0.5)
    args = p.parse_args()

    preds = json.loads(Path(args.predictions).read_text(encoding="utf-8"))
    gts = json.loads(Path(args.ground_truth).read_text(encoding="utf-8"))

    classes = sorted({g["label"] for g in gts} | {p["label"] for p in preds})
    report = {}
    for cls in classes:
        gt_c = [g for g in gts if g["label"] == cls]
        pr_c = [p for p in preds if p["label"] == cls]
        tp = 0
        used = set()
        for pr in pr_c:
            for i, g in enumerate(gt_c):
                if i in used:
                    continue
                if _iou(pr["box"], g["box"]) >= args.iou:
                    tp += 1
                    used.add(i)
                    break
        fp = max(0, len(pr_c) - tp)
        fn = max(0, len(gt_c) - tp)
        prec = tp / (tp + fp) if (tp + fp) else 0.0
        rec = tp / (tp + fn) if (tp + fn) else 0.0
        report[cls] = {"precision": prec, "recall": rec, "tp": tp, "fp": fp, "fn": fn}

    print(json.dumps(report, indent=2))
    print(
        "Device latency: time FrameHub cable pass on a mid-range phone; "
        "target <120ms per cable inference at ~1–2 Hz."
    )


def _iou(a, b):
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    union = (ax2 - ax1) * (ay2 - ay1) + (bx2 - bx1) * (by2 - by1) - inter
    return inter / union if union else 0.0


if __name__ == "__main__":
    main()
