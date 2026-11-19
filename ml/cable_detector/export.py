"""Copy trained TFLite + labels into the app asset folders."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

DEFAULT_LABELS = [
    "charging_cable",
    "usb_c_cable",
    "lightning_cable",
    "micro_usb_cable",
    "hdmi_cable",
    "power_cord",
    "extension_cord",
    "ethernet_cable",
    "headphone_cable",
    "charger_adapter",
    "power_strip",
]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--tflite", type=str, required=True)
    p.add_argument("--labels", type=str, default="")
    p.add_argument(
        "--out_dir",
        type=str,
        default="packages/oriente_native/android/src/main/assets/models",
    )
    args = p.parse_args()

    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.tflite, out / "cable_detector.tflite")
    labels_path = out / "cable_labels.txt"
    if args.labels:
        shutil.copy2(args.labels, labels_path)
    else:
        labels_path.write_text("\n".join(DEFAULT_LABELS) + "\n", encoding="utf-8")
    print("Wrote", out / "cable_detector.tflite")
    print("Wrote", labels_path)


if __name__ == "__main__":
    main()
