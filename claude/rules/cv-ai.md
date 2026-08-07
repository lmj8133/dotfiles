---
scope: Computer vision / ML development (training + inference)
trigger: Python files importing torch, cv2, tensorflow; training / inference scripts; dataset handling
---

# Computer Vision / ML Rules

## Environment & Dependencies

<!-- UV_ONLY_START -->
* **Python toolchain: uv** (per global §5). Use `uv run python <script>.py` and `uv add <pkg>`; do not invent `pip install` instructions unless the project clearly uses pip directly.
<!-- UV_ONLY_END -->
* Pin major frameworks (`torch`, `numpy`, `opencv-python`) in `pyproject.toml`. CUDA-bound packages (`torch`) are version-sensitive — do not bump them as a side effect of unrelated work.

## Deployment Targets — Desktop GPU vs Edge

Code may need to run on **both desktop GPU and edge devices**. Assume both unless told otherwise.

* **Do not hardcode `.cuda()` or `device='cuda'`.** Use a resolved device:

  ```python
  device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
  model.to(device)
  ```

* Avoid CUDA-only ops where a portable equivalent exists.
* Memory footprint matters on edge: prefer streaming / chunked processing over loading whole tensors when the input size is unbounded.
* **Desktop inference defaults to plain PyTorch eager mode.** Do not introduce `torch.compile`, TorchScript, or graph-mode conversion on your own initiative — they add complexity and break debuggability.

## OpenCV — Watch for Vendor Forks

* OpenCV API on **edge targets is sometimes a vendor-modified fork** (MCU SDK ships its own `cv2`). Do not assume desktop-OpenCV behavior carries over.
  * If a function behaves unexpectedly on edge, suspect the fork before assuming a bug.
  * Do not preemptively write polyfills / shims for "missing" APIs — wait until a real incompatibility appears, then handle that specific call.
* **BGR vs RGB**: OpenCV reads/writes BGR by default; `torchvision`, `PIL`, and most model inputs are RGB. **Verify channel order** at every boundary between cv2 and the model.

## Datasets

* Dataset files live **on local disk**. Paths must be **parameterized** (CLI flag, env var, or config) — **never hardcode** paths to a developer's local directory in committed code. Hardcoded paths break portability and prevent collaborators from running the project.
* Don't introduce dataset versioning tooling (DVC / cloud sync) on your own initiative.

## Reproducibility

* **Seed control is not a project requirement.** Do not add `torch.manual_seed`, `np.random.seed`, `random.seed`, or determinism flags (`torch.backends.cudnn.deterministic`) unless explicitly asked.

## Experiment Tracking

* **W&B is the intended tracker** (introduction in progress, not yet established).
* When writing new training code: **structure it so logging is easy to add later** — keep loss / metric values flowing through a single point that could call `wandb.log()`, rather than scattered `print` calls.
* **Do not add `wandb.init()` or W&B imports on your own initiative.** If a task explicitly asks for tracking, confirm before wiring it up — the project may not have a W&B account configured yet.

## Model Checkpoints

* **Never overwrite an existing checkpoint** by default. If saving to a fixed path, append a suffix (epoch, timestamp, metric) or use a unique filename.

## Model Export / Deployment

* Export format depends on target platform — **do not assume ONNX, TensorRT, or any specific runtime**. Ask which target before writing export code.
* Common cases:
  * Desktop GPU inference → keep PyTorch eager mode
  * Jetson / edge GPU → ONNX → TensorRT
  * Vendor MCU → vendor SDK's converter (often proprietary)
* When a project targets **both desktop and edge**, confirm whether it's one shared model script with a runtime-resolved device, or two separate code paths. This affects how device abstraction and export code are structured — don't assume.
* Quantization, pruning, and graph optimization are **target-specific** and lossy. Don't apply them without confirming the target's tolerance.

## Pre-flight Checks (assume both targets, don't ask)

Default assumptions — proceed without asking, state the assumption in the response if it shaped the code:

* **Device target** — assume both desktop and edge unless the codebase makes one obvious. Use `torch.device('cuda' if torch.cuda.is_available() else 'cpu')`, never hardcode `.cuda()`. No need to ask "desktop or edge?"
* **Dataset path** — read from CLI flag / env var / config. Pick a sensible default, document it; don't ask the user to specify before writing code
* **W&B / experiment tracking** — do NOT add `wandb.init()` on your own initiative. Structure code so logging is easy to add later, but leave it out
* **Export format** — only relevant when generating deployment code. If you reach that point with no signal in the project, then ask
