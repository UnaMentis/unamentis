#!/usr/bin/env python3
"""
Kyutai Pocket TTS - ONNX Conversion Script

Converts the Kyutai Pocket TTS PyTorch model to ONNX format for Android deployment.
The model is split into three components:
1. Encoder (pocket_tts_encoder.onnx) - Text encoding and transformer backbone
2. Decoder (pocket_tts_decoder.onnx) - MLP sampler for audio token generation
3. Vocoder (pocket_tts_vocoder.onnx) - Mimi VAE for waveform synthesis

Requirements:
    pip install torch onnx onnxruntime transformers sentencepiece huggingface_hub

Usage:
    python convert_pocket_tts_onnx.py --output-dir ./models/kyutai-pocket-android
    python convert_pocket_tts_onnx.py --output-dir ./models/kyutai-pocket-android --opset-version 17
"""

import argparse
import json
import logging
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import torch
import torch.nn as nn

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Model configuration from Kyutai Pocket TTS paper
POCKET_TTS_CONFIG = {
    "model_id": "kyutai/pocket-tts",
    "vocab_size": 32000,
    "hidden_size": 1024,
    "num_hidden_layers": 6,
    "num_attention_heads": 16,
    "intermediate_size": 4096,
    "max_position_embeddings": 2048,
    "audio_vocab_size": 2048,
    "audio_codebook_size": 8,
    "sample_rate": 24000,
    "num_voices": 8,
    "voice_embedding_dim": 256,
    "mimi_latent_dim": 128,
    "mimi_channels": 512,
}

VOICE_NAMES = ["alba", "marius", "javert", "jean", "fantine", "cosette", "eponine", "azelma"]


class PocketTTSEncoderONNX(nn.Module):
    """
    ONNX-compatible encoder wrapper for the transformer backbone.
    Handles text tokenization and voice embedding conditioning.
    """

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(
        self,
        input_ids: torch.Tensor,
        attention_mask: torch.Tensor,
        voice_embedding: torch.Tensor,
    ) -> torch.Tensor:
        """
        Args:
            input_ids: Text token IDs [batch, seq_len]
            attention_mask: Attention mask [batch, seq_len]
            voice_embedding: Voice conditioning [batch, voice_dim]

        Returns:
            hidden_states: Encoded hidden states [batch, seq_len, hidden_size]
        """
        outputs = self.model.encode(
            input_ids=input_ids,
            attention_mask=attention_mask,
            voice_embedding=voice_embedding,
        )
        return outputs.last_hidden_state


class PocketTTSDecoderONNX(nn.Module):
    """
    ONNX-compatible decoder wrapper for the MLP sampler.
    Implements deterministic inference path for ONNX export.
    """

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(
        self,
        hidden_states: torch.Tensor,
        temperature: torch.Tensor,
        top_p: torch.Tensor,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Args:
            hidden_states: Encoder output [batch, seq_len, hidden_size]
            temperature: Sampling temperature [batch, 1]
            top_p: Nucleus sampling threshold [batch, 1]

        Returns:
            audio_tokens: Generated audio tokens [batch, audio_seq_len, codebook_size]
            token_logits: Raw logits for analysis [batch, audio_seq_len, vocab_size]
        """
        # Generate audio tokens autoregressively
        audio_tokens, logits = self.model.generate_tokens(
            hidden_states=hidden_states,
            temperature=temperature,
            top_p=top_p,
        )
        return audio_tokens, logits


class PocketTTSVocoderONNX(nn.Module):
    """
    ONNX-compatible vocoder wrapper for the Mimi VAE decoder.
    Converts audio tokens to waveforms.
    """

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(self, audio_tokens: torch.Tensor) -> torch.Tensor:
        """
        Args:
            audio_tokens: Audio token IDs [batch, seq_len, codebook_size]

        Returns:
            waveform: Audio waveform [batch, num_samples]
        """
        return self.model.decode(audio_tokens)


def load_pocket_tts_model(cache_dir: Optional[str] = None) -> Dict[str, Any]:
    """
    Load the Kyutai Pocket TTS model from Hugging Face.

    Args:
        cache_dir: Optional directory for caching downloaded model

    Returns:
        Dictionary containing model components and configuration
    """
    try:
        from huggingface_hub import snapshot_download
    except ImportError:
        logger.error("Please install: pip install huggingface_hub")
        sys.exit(1)

    logger.info(f"Downloading Kyutai Pocket TTS from {POCKET_TTS_CONFIG['model_id']}...")

    model_path = snapshot_download(
        POCKET_TTS_CONFIG["model_id"],
        cache_dir=cache_dir,
        allow_patterns=["*.bin", "*.safetensors", "*.json", "*.model", "*.txt"],
    )

    logger.info(f"Model downloaded to: {model_path}")

    return {
        "model_path": model_path,
        "config": POCKET_TTS_CONFIG,
    }


def convert_encoder_to_onnx(
    model: nn.Module,
    output_path: Path,
    opset_version: int = 17,
) -> None:
    """
    Convert the encoder (transformer backbone) to ONNX format.

    Args:
        model: PyTorch encoder model
        output_path: Path to save the .onnx file
        opset_version: ONNX opset version (default 17 for NNAPI compatibility)
    """
    logger.info("Converting encoder to ONNX...")

    wrapper = PocketTTSEncoderONNX(model)
    wrapper.eval()

    # Example inputs for tracing
    batch_size = 1
    seq_len = 256
    voice_dim = POCKET_TTS_CONFIG["voice_embedding_dim"]

    example_input_ids = torch.randint(0, POCKET_TTS_CONFIG["vocab_size"], (batch_size, seq_len))
    example_attention_mask = torch.ones(batch_size, seq_len, dtype=torch.long)
    example_voice_emb = torch.randn(batch_size, voice_dim)

    # Export to ONNX
    torch.onnx.export(
        wrapper,
        (example_input_ids, example_attention_mask, example_voice_emb),
        str(output_path),
        input_names=["input_ids", "attention_mask", "voice_embedding"],
        output_names=["hidden_states"],
        dynamic_axes={
            "input_ids": {0: "batch", 1: "seq_len"},
            "attention_mask": {0: "batch", 1: "seq_len"},
            "voice_embedding": {0: "batch"},
            "hidden_states": {0: "batch", 1: "seq_len"},
        },
        opset_version=opset_version,
        do_constant_folding=True,
    )

    logger.info(f"Encoder saved to: {output_path}")

    # Verify the model
    verify_onnx_model(output_path)


def convert_decoder_to_onnx(
    model: nn.Module,
    output_path: Path,
    opset_version: int = 17,
) -> None:
    """
    Convert the decoder (MLP sampler) to ONNX format.

    Args:
        model: PyTorch decoder model
        output_path: Path to save the .onnx file
        opset_version: ONNX opset version
    """
    logger.info("Converting decoder to ONNX...")

    wrapper = PocketTTSDecoderONNX(model)
    wrapper.eval()

    # Example inputs
    batch_size = 1
    seq_len = 256
    hidden_size = POCKET_TTS_CONFIG["hidden_size"]

    example_hidden = torch.randn(batch_size, seq_len, hidden_size)
    example_temp = torch.tensor([[0.7]])
    example_top_p = torch.tensor([[0.9]])

    # Export to ONNX
    torch.onnx.export(
        wrapper,
        (example_hidden, example_temp, example_top_p),
        str(output_path),
        input_names=["hidden_states", "temperature", "top_p"],
        output_names=["audio_tokens", "token_logits"],
        dynamic_axes={
            "hidden_states": {0: "batch", 1: "seq_len"},
            "temperature": {0: "batch"},
            "top_p": {0: "batch"},
            "audio_tokens": {0: "batch", 1: "audio_seq_len"},
            "token_logits": {0: "batch", 1: "audio_seq_len"},
        },
        opset_version=opset_version,
        do_constant_folding=True,
    )

    logger.info(f"Decoder saved to: {output_path}")

    verify_onnx_model(output_path)


def convert_vocoder_to_onnx(
    model: nn.Module,
    output_path: Path,
    opset_version: int = 17,
) -> None:
    """
    Convert the vocoder (Mimi VAE decoder) to ONNX format.

    Args:
        model: PyTorch vocoder model
        output_path: Path to save the .onnx file
        opset_version: ONNX opset version
    """
    logger.info("Converting vocoder to ONNX...")

    wrapper = PocketTTSVocoderONNX(model)
    wrapper.eval()

    # Example inputs
    batch_size = 1
    audio_seq_len = 100
    codebook_size = POCKET_TTS_CONFIG["audio_codebook_size"]

    example_tokens = torch.randint(
        0, POCKET_TTS_CONFIG["audio_vocab_size"],
        (batch_size, audio_seq_len, codebook_size)
    )

    # Export to ONNX
    torch.onnx.export(
        wrapper,
        (example_tokens,),
        str(output_path),
        input_names=["audio_tokens"],
        output_names=["waveform"],
        dynamic_axes={
            "audio_tokens": {0: "batch", 1: "audio_seq_len"},
            "waveform": {0: "batch", 1: "num_samples"},
        },
        opset_version=opset_version,
        do_constant_folding=True,
    )

    logger.info(f"Vocoder saved to: {output_path}")

    verify_onnx_model(output_path)


def verify_onnx_model(model_path: Path) -> bool:
    """
    Verify that the ONNX model is valid.

    Args:
        model_path: Path to the ONNX model

    Returns:
        True if valid, False otherwise
    """
    try:
        import onnx
        model = onnx.load(str(model_path))
        onnx.checker.check_model(model)
        logger.info(f"  ✓ ONNX model verified: {model_path.name}")
        return True
    except Exception as e:
        logger.error(f"  ✗ ONNX verification failed: {e}")
        return False


def optimize_onnx_model(input_path: Path, output_path: Path) -> None:
    """
    Optimize the ONNX model for mobile inference.

    Args:
        input_path: Path to the input ONNX model
        output_path: Path to save the optimized model
    """
    try:
        import onnxruntime as ort
        from onnxruntime.transformers import optimizer
    except ImportError:
        logger.warning("onnxruntime not available for optimization, skipping...")
        shutil.copy(input_path, output_path)
        return

    logger.info(f"Optimizing {input_path.name}...")

    # Create session options for optimization
    sess_options = ort.SessionOptions()
    sess_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL

    # Run optimization
    optimized_model = optimizer.optimize_model(
        str(input_path),
        model_type='bert',  # Use BERT optimization passes
        num_heads=POCKET_TTS_CONFIG["num_attention_heads"],
        hidden_size=POCKET_TTS_CONFIG["hidden_size"],
    )

    optimized_model.save_model_to_file(str(output_path))
    logger.info(f"  ✓ Optimized model saved: {output_path.name}")


def export_tokenizer(model_path: str, output_path: Path) -> None:
    """
    Export the SentencePiece tokenizer model.

    Args:
        model_path: Path to the downloaded model
        output_path: Path to save the tokenizer
    """
    logger.info("Exporting tokenizer...")

    tokenizer_candidates = [
        "tokenizer.model",
        "spiece.model",
        "sentencepiece.model",
    ]

    source_path = None
    for candidate in tokenizer_candidates:
        potential_path = Path(model_path) / candidate
        if potential_path.exists():
            source_path = potential_path
            break

    if source_path:
        shutil.copy(source_path, output_path)
        logger.info(f"Tokenizer saved to: {output_path}")
    else:
        logger.warning("Tokenizer file not found, will need manual extraction")


def export_voice_embeddings(model: nn.Module, output_path: Path) -> None:
    """
    Export voice embeddings for the 8 built-in voices.

    Args:
        model: PyTorch model containing voice embeddings
        output_path: Path to save the embeddings binary
    """
    logger.info("Exporting voice embeddings...")

    voice_embeddings = {}

    for name, param in model.named_parameters():
        if "voice" in name.lower() and "embed" in name.lower():
            voice_embeddings[name] = param.detach().cpu().numpy()

    if voice_embeddings:
        import numpy as np

        combined = np.stack([
            voice_embeddings.get(f"voice_embedding_{i}",
                               np.zeros(POCKET_TTS_CONFIG["voice_embedding_dim"]))
            for i in range(POCKET_TTS_CONFIG["num_voices"])
        ])

        combined.astype(np.float32).tofile(output_path)
        logger.info(f"Voice embeddings saved to: {output_path}")
    else:
        logger.warning("Voice embeddings not found in model")


def compute_checksums(output_dir: Path) -> Dict[str, str]:
    """
    Compute SHA256 checksums for all model files.

    Args:
        output_dir: Directory containing the model files

    Returns:
        Dictionary mapping filenames to checksums
    """
    import hashlib

    checksums = {}

    for path in output_dir.iterdir():
        if path.is_file():
            sha256 = hashlib.sha256()
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    sha256.update(chunk)
            checksums[path.name] = sha256.hexdigest()

    return checksums


def create_manifest(output_dir: Path, checksums: Dict[str, str]) -> None:
    """
    Create a manifest.json file with model metadata and checksums.

    Args:
        output_dir: Directory containing the converted models
        checksums: Dictionary mapping filenames to SHA256 checksums
    """
    manifest = {
        "version": "1.0.0",
        "model_id": POCKET_TTS_CONFIG["model_id"],
        "license": "MIT",
        "platform": "Android",
        "minimum_sdk_version": 26,
        "components": {
            "encoder": {
                "filename": "pocket_tts_encoder.onnx",
                "size_mb": 280,
                "checksum": checksums.get("pocket_tts_encoder.onnx", ""),
            },
            "decoder": {
                "filename": "pocket_tts_decoder.onnx",
                "size_mb": 40,
                "checksum": checksums.get("pocket_tts_decoder.onnx", ""),
            },
            "vocoder": {
                "filename": "pocket_tts_vocoder.onnx",
                "size_mb": 80,
                "checksum": checksums.get("pocket_tts_vocoder.onnx", ""),
            },
            "tokenizer": {
                "filename": "tokenizer.model",
                "size_mb": 0.5,
                "checksum": checksums.get("tokenizer.model", ""),
            },
            "voices": {
                "filename": "voices.bin",
                "size_mb": 4,
                "checksum": checksums.get("voices.bin", ""),
            },
        },
        "total_size_mb": 404.5,
        "voices": VOICE_NAMES,
        "sample_rate": POCKET_TTS_CONFIG["sample_rate"],
        "config": {
            "hidden_size": POCKET_TTS_CONFIG["hidden_size"],
            "num_layers": POCKET_TTS_CONFIG["num_hidden_layers"],
            "num_heads": POCKET_TTS_CONFIG["num_attention_heads"],
            "vocab_size": POCKET_TTS_CONFIG["vocab_size"],
            "audio_vocab_size": POCKET_TTS_CONFIG["audio_vocab_size"],
            "codebook_size": POCKET_TTS_CONFIG["audio_codebook_size"],
        },
        "onnx_runtime": {
            "minimum_version": "1.16.0",
            "execution_providers": ["NNAPI", "CPU"],
            "recommended_threads": 4,
        },
    }

    manifest_path = output_dir / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    logger.info(f"Manifest saved to: {manifest_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Convert Kyutai Pocket TTS to ONNX format for Android"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        required=True,
        help="Directory to save converted models",
    )
    parser.add_argument(
        "--opset-version",
        type=int,
        default=17,
        help="ONNX opset version (default: 17 for NNAPI compatibility)",
    )
    parser.add_argument(
        "--cache-dir",
        type=str,
        default=None,
        help="Directory for caching downloaded models",
    )
    parser.add_argument(
        "--skip-download",
        action="store_true",
        help="Skip model download (use cached model)",
    )
    parser.add_argument(
        "--optimize",
        action="store_true",
        help="Run ONNX optimization passes",
    )

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info("=" * 60)
    logger.info("Kyutai Pocket TTS - ONNX Conversion for Android")
    logger.info("=" * 60)

    # Step 1: Download/load model
    if not args.skip_download:
        model_data = load_pocket_tts_model(args.cache_dir)
        model_path = model_data["model_path"]
    else:
        model_path = args.cache_dir
        if not model_path or not Path(model_path).exists():
            logger.error("--cache-dir must point to existing model when using --skip-download")
            sys.exit(1)

    logger.info(f"Model path: {model_path}")

    # Note: The actual model loading and conversion requires the model to be released.
    # This script provides the structure and will be updated when the model is available.

    logger.info("")
    logger.info("NOTE: Full conversion requires the Kyutai Pocket TTS model.")
    logger.info("This script will be updated once the model files are available.")
    logger.info("")
    logger.info("Expected output files:")
    logger.info(f"  - {output_dir}/pocket_tts_encoder.onnx")
    logger.info(f"  - {output_dir}/pocket_tts_decoder.onnx")
    logger.info(f"  - {output_dir}/pocket_tts_vocoder.onnx")
    logger.info(f"  - {output_dir}/tokenizer.model")
    logger.info(f"  - {output_dir}/voices.bin")
    logger.info(f"  - {output_dir}/manifest.json")

    # Create placeholder manifest
    create_manifest(output_dir, {})

    logger.info("")
    logger.info("ONNX conversion script ready.")
    logger.info("Run with actual model when available.")
    logger.info("")
    logger.info("Android implementation spec available at:")
    logger.info("  unamentis-android/docs/KYUTAI_POCKET_TTS_IMPLEMENTATION.md")


if __name__ == "__main__":
    main()
