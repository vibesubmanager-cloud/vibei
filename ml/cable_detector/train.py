"""Colab-ready MediaPipe Model Maker object detection training for cables.

Run in Google Colab with a GPU. Requires a Pascal VOC or COCO-format dataset
under ./data with the classes listed in README.md.
"""

from __future__ import annotations

import argparse
from pathlib import Path

# mediapipe-model-maker is installed in Colab via:
#   !pip install mediapipe-model-maker


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_dir", type=str, required=True)
    parser.add_argument("--export_dir", type=str, default="export")
    parser.add_argument("--epochs", type=int, default=40)
    parser.add_argument("--batch_size", type=int, default=8)
    parser.add_argument("--input_size", type=int, default=512)
    args = parser.parse_args()

    from mediapipe_model_maker import object_detector

    data_dir = Path(args.data_dir)
    train_data = object_detector.Dataset.from_coco_folder(
        str(data_dir / "train"),
    )
    val_data = object_detector.Dataset.from_coco_folder(
        str(data_dir / "val"),
    )

    spec = object_detector.SupportedModels.EFFICIENTDETLITE0
    hparams = object_detector.HParams(
        export_dir=args.export_dir,
        epochs=args.epochs,
        batch_size=args.batch_size,
    )
    options = object_detector.ObjectDetectorOptions(
        supported_model=spec,
        hparams=hparams,
    )
    # Larger input (≥512) via model options when supported by the installed
    # mediapipe-model-maker version; otherwise re-export with converter.
    model = object_detector.ObjectDetector.create(
        train_data=train_data,
        validation_data=val_data,
        options=options,
    )
    model.export_model()
    print("Exported to", args.export_dir)
    print("Next: run export.py to copy tflite + labels into app assets.")


if __name__ == "__main__":
    main()
