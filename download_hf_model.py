#!/usr/bin/env python3
"""
Download Hugging Face models to a specified local path.

Usage:
    python download_hf_model.py <model_name> <save_path>

Example:
    python download_hf_model.py meta-llama/Llama-2-7b-hf ./models/llama2-7b
"""

import argparse
import os
from pathlib import Path
from huggingface_hub import snapshot_download


def download_model(model_name: str, save_path: str):
    """
    Download a Hugging Face model to the specified path.

    Args:
        model_name: The HuggingFace model identifier (e.g., "meta-llama/Llama-2-7b-hf")
        save_path: Local directory path where the model will be saved
    """
    print(f"Downloading model: {model_name}")
    print(f"Save path: {save_path}")

    # Create the save directory if it doesn't exist
    save_path = Path(save_path)
    save_path.mkdir(parents=True, exist_ok=True)

    try:
        # Download the entire model repository
        downloaded_path = snapshot_download(
            repo_id=model_name,
            local_dir=save_path,
            local_dir_use_symlinks=False,  # Don't use symlinks, copy actual files
            resume_download=True,  # Resume if download was interrupted
        )

        print(f"\n✓ Model successfully downloaded to: {downloaded_path}")
        print(f"\nDownloaded files:")
        for file in sorted(save_path.rglob("*")):
            if file.is_file():
                size_mb = file.stat().st_size / (1024 * 1024)
                print(f"  - {file.relative_to(save_path)} ({size_mb:.2f} MB)")

    except Exception as e:
        print(f"\n✗ Error downloading model: {e}")
        raise


def main():
    parser = argparse.ArgumentParser(
        description="Download Hugging Face models to a local path",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Download Llama 2 7B
  python download_hf_model.py meta-llama/Llama-2-7b-hf ./models/llama2-7b

  # Download Qwen model
  python download_hf_model.py Qwen/Qwen2.5-7B-Instruct ./models/qwen2.5-7b

  # Download BERT
  python download_hf_model.py bert-base-uncased ./models/bert-base

Note:
  - You may need to set HF_TOKEN environment variable for gated models
  - Use 'huggingface-cli login' to authenticate for private/gated models
        """
    )

    parser.add_argument(
        "model_name",
        type=str,
        help="HuggingFace model identifier (e.g., 'meta-llama/Llama-2-7b-hf')"
    )

    parser.add_argument(
        "save_path",
        type=str,
        help="Local directory path to save the model"
    )

    parser.add_argument(
        "--token",
        type=str,
        default=None,
        help="HuggingFace API token (optional, for private/gated models)"
    )

    args = parser.parse_args()

    # Set token if provided
    if args.token:
        os.environ["HF_TOKEN"] = args.token

    download_model(args.model_name, args.save_path)


if __name__ == "__main__":
    main()
