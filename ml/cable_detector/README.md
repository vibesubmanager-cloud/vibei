# Offline cable detector

Trains a MediaPipe Model Maker EfficientDet-Lite object detector (Apache 2.0) for cable classes used by VIBEI FrameHub.

## Classes

1. `charging_cable`
2. `usb_c_cable`
3. `lightning_cable`
4. `micro_usb_cable`
5. `hdmi_cable`
6. `power_cord`
7. `extension_cord`
8. `ethernet_cable`
9. `headphone_cable`
10. `charger_adapter`
11. `power_strip`

Canonical runtime merge label is often `cable` (see `CableDetectorModule`).

## Data plan

- At least **400 varied photos per class**.
- Vary surfaces (desk, floor, fabric, outdoor), lighting, tangled vs straight, near vs far.
- Include **negative images with no cables**.
- Label with Label Studio or CVAT (bounding boxes).
- **Check the license of every public dataset before use.** Do not train on data you cannot redistribute or whose license forbids model training.

## Scripts

- `train_colab.ipynb` / `train.py` — Colab-ready MediaPipe Model Maker training (input ≥ 512).
- `evaluate.py` — precision/recall per class + device latency notes.
- `export.py` — writes `assets/models/cable_detector.tflite` and `assets/models/cable_labels.txt`.

Swap the exported files into `apps/oriente_app/assets/models/` (or the native plugin assets path used by MediaPipe). The app loads whatever is present; missing files disable only offline cable detection.
