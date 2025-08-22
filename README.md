## Setup Notes

This repo uses Git LFS for large model artifacts (e.g., *.onnx, *.pt, *.bin, *.safetensors, *.ckpt).

After cloning, run:

    git lfs install
    git lfs pull

This ensures required voice/LLM models are downloaded before running docker compose up.
## Quickstart

```bash
git clone https://github.com/SirChako/chillchill-capsule.git
cd chillchill-capsule
git lfs install && git lfs pull
docker compose up
```

