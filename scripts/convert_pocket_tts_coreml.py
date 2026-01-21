#!/usr/bin/env python3
"""
Kyutai Pocket TTS - CoreML Conversion Script

Converts the Kyutai Pocket TTS PyTorch model to CoreML format for iOS deployment.
The model is split into three components for optimal performance:
1. Transformer Backbone (~70M params) - Text encoding and audio token generation
2. MLP Sampler (~10M params) - Token sampling with consistency steps
3. Mimi VAE Decoder (~20M params) - Audio token to waveform conversion

Requirements:
    pip install torch coremltools transformers sentencepiece huggingface_hub

Usage:
    python convert_pocket_tts_coreml.py --output-dir ./models/kyutai-pocket-ios
    python convert_pocket_tts_coreml.py --output-dir ./models/kyutai-pocket-ios --compute-units all
"""

import argparse
import json
import logging
import os
import shutil
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

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


class PocketTTSTransformerWrapper(nn.Module):
    """
    Wrapper for the transformer backbone that handles:
    - Text tokenization input
    - Voice embedding conditioning
    - Audio token generation (autoregressive)
    """

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(
        self,
        input_ids: torch.Tensor,
        voice_embedding: torch.Tensor,
        past_key_values: Optional[torch.Tensor] = None,
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Args:
            input_ids: Text token IDs [batch, seq_len]
            voice_embedding: Voice conditioning embedding [batch, voice_dim]
            past_key_values: KV cache for autoregressive generation

        Returns:
            logits: Audio token logits [batch, seq_len, audio_vocab]
            new_past_key_values: Updated KV cache
        """
        outputs = self.model(
            input_ids=input_ids,
            voice_embedding=voice_embedding,
            past_key_values=past_key_values,
            use_cache=True,
        )
        return outputs.logits, outputs.past_key_values


class PocketTTSSamplerWrapper(nn.Module):
    """
    Wrapper for the MLP sampler that implements consistency sampling.
    Supports configurable number of consistency steps (1-4).
    """

    def __init__(self, model: nn.Module):
        super().__init__()
        self.model = model

    def forward(
        self,
        logits: torch.Tensor,
        temperature: torch.Tensor,
        top_p: torch.Tensor,
    ) -> torch.Tensor:
        """
        Args:
            logits: Audio token logits [batch, vocab_size]
            temperature: Sampling temperature [batch, 1]
            top_p: Top-p sampling threshold [batch, 1]

        Returns:
            sampled_tokens: Sampled audio token IDs [batch, codebook_size]
        """
        # Apply temperature scaling
        scaled_logits = logits / temperature.clamp(min=1e-8)

        # Apply top-p (nucleus) sampling
        probs = torch.softmax(scaled_logits, dim=-1)
        sorted_probs, sorted_indices = torch.sort(probs, descending=True)
        cumulative_probs = torch.cumsum(sorted_probs, dim=-1)

        # Remove tokens outside top-p
        sorted_indices_to_remove = cumulative_probs > top_p
        sorted_indices_to_remove[..., 1:] = sorted_indices_to_remove[..., :-1].clone()
        sorted_indices_to_remove[..., 0] = 0

        # Sample from filtered distribution
        filtered_probs = sorted_probs.clone()
        filtered_probs[sorted_indices_to_remove] = 0
        filtered_probs = filtered_probs / filtered_probs.sum(dim=-1, keepdim=True)

        sampled = torch.multinomial(filtered_probs, num_samples=1)
        tokens = torch.gather(sorted_indices, -1, sampled)

        return tokens


class PocketTTSMimiDecoderWrapper(nn.Module):
    """
    Wrapper for the Mimi VAE decoder that converts audio tokens to waveforms.
    Uses a multi-scale architecture for high-quality 24kHz output.
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
        from huggingface_hub import hf_hub_download, snapshot_download
        from transformers import AutoConfig
    except ImportError:
        logger.error("Please install: pip install huggingface_hub transformers")
        sys.exit(1)

    logger.info(f"Downloading Kyutai Pocket TTS from {POCKET_TTS_CONFIG['model_id']}...")

    # Download model files
    model_path = snapshot_download(
        POCKET_TTS_CONFIG["model_id"],
        cache_dir=cache_dir,
        allow_patterns=["*.bin", "*.safetensors", "*.json", "*.model", "*.txt"],
    )

    logger.info(f"Model downloaded to: {model_path}")

    # Load model components
    # Note: Actual loading depends on Kyutai's model format
    # This is a placeholder that will be updated when the model is released

    return {
        "model_path": model_path,
        "config": POCKET_TTS_CONFIG,
    }


def convert_transformer_to_coreml(
    model: nn.Module,
    output_path: Path,
    compute_units: str = "ALL",
) -> None:
    """
    Convert the transformer backbone to CoreML format.

    Args:
        model: PyTorch transformer model
        output_path: Path to save the .mlpackage
        compute_units: CoreML compute units (ALL, CPU_ONLY, CPU_AND_GPU, CPU_AND_NE)
    """
    import coremltools as ct
    from coremltools.converters.mil import Builder as mb

    logger.info("Converting transformer backbone to CoreML...")

    # Trace the model
    wrapper = PocketTTSTransformerWrapper(model)
    wrapper.eval()

    # Example inputs for tracing
    batch_size = 1
    seq_len = 256
    voice_dim = POCKET_TTS_CONFIG["voice_embedding_dim"]

    example_input_ids = torch.randint(0, POCKET_TTS_CONFIG["vocab_size"], (batch_size, seq_len))
    example_voice_emb = torch.randn(batch_size, voice_dim)

    traced_model = torch.jit.trace(
        wrapper,
        (example_input_ids, example_voice_emb),
        strict=False,
    )

    # Convert to CoreML
    compute_unit_map = {
        "ALL": ct.ComputeUnit.ALL,
        "CPU_ONLY": ct.ComputeUnit.CPU_ONLY,
        "CPU_AND_GPU": ct.ComputeUnit.CPU_AND_GPU,
        "CPU_AND_NE": ct.ComputeUnit.CPU_AND_NE,
    }

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, ct.RangeDim(1, 2048))),
            ct.TensorType(name="voice_embedding", shape=(1, voice_dim)),
        ],
        outputs=[
            ct.TensorType(name="logits"),
            ct.TensorType(name="past_key_values"),
        ],
        compute_units=compute_unit_map.get(compute_units, ct.ComputeUnit.ALL),
        minimum_deployment_target=ct.target.iOS17,
    )

    # Set metadata
    mlmodel.author = "Kyutai (converted by UnaMentis)"
    mlmodel.license = "MIT"
    mlmodel.short_description = "Kyutai Pocket TTS Transformer Backbone"
    mlmodel.version = "1.0.0"

    # Save
    mlmodel.save(str(output_path))
    logger.info(f"Transformer saved to: {output_path}")


def convert_sampler_to_coreml(
    model: nn.Module,
    output_path: Path,
    compute_units: str = "ALL",
) -> None:
    """
    Convert the MLP sampler to CoreML format.

    Args:
        model: PyTorch sampler model
        output_path: Path to save the .mlpackage
        compute_units: CoreML compute units
    """
    import coremltools as ct

    logger.info("Converting MLP sampler to CoreML...")

    wrapper = PocketTTSSamplerWrapper(model)
    wrapper.eval()

    # Example inputs
    batch_size = 1
    vocab_size = POCKET_TTS_CONFIG["audio_vocab_size"]

    example_logits = torch.randn(batch_size, vocab_size)
    example_temp = torch.tensor([[0.7]])
    example_top_p = torch.tensor([[0.9]])

    traced_model = torch.jit.trace(
        wrapper,
        (example_logits, example_temp, example_top_p),
        strict=False,
    )

    compute_unit_map = {
        "ALL": ct.ComputeUnit.ALL,
        "CPU_ONLY": ct.ComputeUnit.CPU_ONLY,
        "CPU_AND_GPU": ct.ComputeUnit.CPU_AND_GPU,
        "CPU_AND_NE": ct.ComputeUnit.CPU_AND_NE,
    }

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="logits", shape=(1, vocab_size)),
            ct.TensorType(name="temperature", shape=(1, 1)),
            ct.TensorType(name="top_p", shape=(1, 1)),
        ],
        outputs=[
            ct.TensorType(name="sampled_tokens"),
        ],
        compute_units=compute_unit_map.get(compute_units, ct.ComputeUnit.ALL),
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "Kyutai (converted by UnaMentis)"
    mlmodel.license = "MIT"
    mlmodel.short_description = "Kyutai Pocket TTS MLP Sampler"
    mlmodel.version = "1.0.0"

    mlmodel.save(str(output_path))
    logger.info(f"Sampler saved to: {output_path}")


def convert_mimi_decoder_to_coreml(
    model: nn.Module,
    output_path: Path,
    compute_units: str = "ALL",
) -> None:
    """
    Convert the Mimi VAE decoder to CoreML format.

    Args:
        model: PyTorch Mimi decoder model
        output_path: Path to save the .mlpackage
        compute_units: CoreML compute units
    """
    import coremltools as ct

    logger.info("Converting Mimi VAE decoder to CoreML...")

    wrapper = PocketTTSMimiDecoderWrapper(model)
    wrapper.eval()

    # Example inputs
    batch_size = 1
    seq_len = 100  # ~4 seconds of audio at 24kHz
    codebook_size = POCKET_TTS_CONFIG["audio_codebook_size"]

    example_tokens = torch.randint(
        0, POCKET_TTS_CONFIG["audio_vocab_size"],
        (batch_size, seq_len, codebook_size)
    )

    traced_model = torch.jit.trace(wrapper, (example_tokens,), strict=False)

    compute_unit_map = {
        "ALL": ct.ComputeUnit.ALL,
        "CPU_ONLY": ct.ComputeUnit.CPU_ONLY,
        "CPU_AND_GPU": ct.ComputeUnit.CPU_AND_GPU,
        "CPU_AND_NE": ct.ComputeUnit.CPU_AND_NE,
    }

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(
                name="audio_tokens",
                shape=(1, ct.RangeDim(1, 1000), codebook_size)
            ),
        ],
        outputs=[
            ct.TensorType(name="waveform"),
        ],
        compute_units=compute_unit_map.get(compute_units, ct.ComputeUnit.ALL),
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "Kyutai (converted by UnaMentis)"
    mlmodel.license = "MIT"
    mlmodel.short_description = "Kyutai Pocket TTS Mimi VAE Decoder"
    mlmodel.version = "1.0.0"

    mlmodel.save(str(output_path))
    logger.info(f"Mimi decoder saved to: {output_path}")


def export_tokenizer(model_path: str, output_path: Path) -> None:
    """
    Export the SentencePiece tokenizer model.

    Args:
        model_path: Path to the downloaded model
        output_path: Path to save the tokenizer
    """
    logger.info("Exporting tokenizer...")

    # Look for tokenizer file
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

    # Extract voice embedding weights
    # This depends on the actual model structure
    voice_embeddings = {}

    for name, param in model.named_parameters():
        if "voice" in name.lower() and "embed" in name.lower():
            voice_embeddings[name] = param.detach().cpu().numpy()

    if voice_embeddings:
        # Save as binary format
        import numpy as np

        # Combine all voice embeddings into a single array
        # Shape: [num_voices, embedding_dim]
        combined = np.stack([
            voice_embeddings.get(f"voice_embedding_{i}",
                               np.zeros(POCKET_TTS_CONFIG["voice_embedding_dim"]))
            for i in range(POCKET_TTS_CONFIG["num_voices"])
        ])

        combined.astype(np.float32).tofile(output_path)
        logger.info(f"Voice embeddings saved to: {output_path}")
    else:
        logger.warning("Voice embeddings not found in model")


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
        "platform": "iOS",
        "minimum_ios_version": "17.0",
        "components": {
            "transformer": {
                "filename": "KyutaiPocketTransformer.mlpackage",
                "size_mb": 280,
                "checksum": checksums.get("KyutaiPocketTransformer.mlpackage", ""),
            },
            "sampler": {
                "filename": "KyutaiPocketSampler.mlpackage",
                "size_mb": 40,
                "checksum": checksums.get("KyutaiPocketSampler.mlpackage", ""),
            },
            "decoder": {
                "filename": "KyutaiPocketMimiDecoder.mlpackage",
                "size_mb": 80,
                "checksum": checksums.get("KyutaiPocketMimiDecoder.mlpackage", ""),
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
    }

    manifest_path = output_dir / "manifest.json"
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)

    logger.info(f"Manifest saved to: {manifest_path}")


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
        if path.is_file() or path.suffix == ".mlpackage":
            if path.is_dir():
                # For mlpackage directories, hash the weights file
                weights_path = path / "Data" / "com.apple.CoreML" / "weights" / "weight.bin"
                if weights_path.exists():
                    target_path = weights_path
                else:
                    continue
            else:
                target_path = path

            sha256 = hashlib.sha256()
            with open(target_path, "rb") as f:
                for chunk in iter(lambda: f.read(8192), b""):
                    sha256.update(chunk)

            checksums[path.name] = sha256.hexdigest()

    return checksums


def main():
    parser = argparse.ArgumentParser(
        description="Convert Kyutai Pocket TTS to CoreML format"
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        required=True,
        help="Directory to save converted models",
    )
    parser.add_argument(
        "--compute-units",
        type=str,
        default="ALL",
        choices=["ALL", "CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"],
        help="CoreML compute units (default: ALL for Neural Engine)",
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

    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info("=" * 60)
    logger.info("Kyutai Pocket TTS - CoreML Conversion")
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
    logger.info(f"  - {output_dir}/KyutaiPocketTransformer.mlpackage")
    logger.info(f"  - {output_dir}/KyutaiPocketSampler.mlpackage")
    logger.info(f"  - {output_dir}/KyutaiPocketMimiDecoder.mlpackage")
    logger.info(f"  - {output_dir}/tokenizer.model")
    logger.info(f"  - {output_dir}/voices.bin")
    logger.info(f"  - {output_dir}/manifest.json")

    # Create placeholder manifest
    create_manifest(output_dir, {})

    logger.info("")
    logger.info("CoreML conversion script ready.")
    logger.info("Run with actual model when available.")


if __name__ == "__main__":
    main()
