import os
from huggingface_hub import snapshot_download

if __name__ == "__main__":
    models = [
        "stabilityai/sdxl-turbo",
        "TencentARC/t2i-adapter-canny-sdxl-1.0",
        "madebyollin/sdxl-vae-fp16-fix"
    ]

    for repo_id in models:
        print(f"Downloading {repo_id}...")
        snapshot_download(repo_id=repo_id)

    print("All models downloaded successfully")
