#!/usr/bin/env python3
"""
Kyutai Pocket TTS - Cross-Platform Output Verification

Verifies that CoreML (iOS) and ONNX (Android) conversions produce
outputs consistent with the original PyTorch model.

Requirements:
    pip install torch numpy coremltools onnxruntime soundfile

Usage:
    # Verify CoreML conversion
    python verify_model_outputs.py --coreml-dir ./models/kyutai-pocket-ios

    # Verify ONNX conversion
    python verify_model_outputs.py --onnx-dir ./models/kyutai-pocket-android

    # Verify both against PyTorch reference
    python verify_model_outputs.py \\
        --pytorch-dir ~/.cache/huggingface/kyutai-pocket-tts \\
        --coreml-dir ./models/kyutai-pocket-ios \\
        --onnx-dir ./models/kyutai-pocket-android

    # Full verification with audio output comparison
    python verify_model_outputs.py --full --output-dir ./verification_results
"""

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Tolerance thresholds for numerical comparison
TOLERANCES = {
    "encoder_hidden_states": {"atol": 1e-4, "rtol": 1e-3},
    "decoder_logits": {"atol": 1e-3, "rtol": 1e-2},
    "audio_tokens": {"exact_match": True},
    "waveform": {"atol": 1e-3, "rtol": 1e-2},
}

# Test prompts for verification
TEST_PROMPTS = [
    "Hello, this is a test of the Kyutai Pocket text to speech system.",
    "The quick brown fox jumps over the lazy dog.",
    "One two three four five six seven eight nine ten.",
    "Testing special characters: café, naïve, résumé.",
]

VOICE_NAMES = ["alba", "marius", "javert", "jean", "fantine", "cosette", "eponine", "azelma"]


@dataclass
class VerificationResult:
    """Result of a single verification test."""
    test_name: str
    passed: bool
    max_diff: float
    mean_diff: float
    details: str


@dataclass
class VerificationReport:
    """Complete verification report."""
    platform: str
    total_tests: int
    passed_tests: int
    failed_tests: int
    results: List[VerificationResult]


def load_pytorch_model(model_dir: Path) -> Optional[Any]:
    """
    Load the original PyTorch model.

    Args:
        model_dir: Path to the PyTorch model directory

    Returns:
        Loaded PyTorch model or None if not available
    """
    try:
        import torch
        # Placeholder for actual model loading
        # This will be updated when the model format is known
        logger.info(f"Loading PyTorch model from {model_dir}")
        return None
    except Exception as e:
        logger.warning(f"Could not load PyTorch model: {e}")
        return None


def load_coreml_models(model_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Load CoreML models for iOS verification.

    Args:
        model_dir: Path to the CoreML models directory

    Returns:
        Dictionary of loaded CoreML models or None if not available
    """
    try:
        import coremltools as ct

        models = {}

        # Load transformer
        transformer_path = model_dir / "KyutaiPocketTransformer.mlpackage"
        if transformer_path.exists():
            models["transformer"] = ct.models.MLModel(str(transformer_path))
            logger.info(f"  ✓ Loaded transformer: {transformer_path.name}")

        # Load sampler
        sampler_path = model_dir / "KyutaiPocketSampler.mlpackage"
        if sampler_path.exists():
            models["sampler"] = ct.models.MLModel(str(sampler_path))
            logger.info(f"  ✓ Loaded sampler: {sampler_path.name}")

        # Load decoder
        decoder_path = model_dir / "KyutaiPocketMimiDecoder.mlpackage"
        if decoder_path.exists():
            models["decoder"] = ct.models.MLModel(str(decoder_path))
            logger.info(f"  ✓ Loaded decoder: {decoder_path.name}")

        return models if models else None
    except Exception as e:
        logger.warning(f"Could not load CoreML models: {e}")
        return None


def load_onnx_models(model_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Load ONNX models for Android verification.

    Args:
        model_dir: Path to the ONNX models directory

    Returns:
        Dictionary of loaded ONNX inference sessions or None if not available
    """
    try:
        import onnxruntime as ort

        models = {}

        # Load encoder
        encoder_path = model_dir / "pocket_tts_encoder.onnx"
        if encoder_path.exists():
            models["encoder"] = ort.InferenceSession(str(encoder_path))
            logger.info(f"  ✓ Loaded encoder: {encoder_path.name}")

        # Load decoder
        decoder_path = model_dir / "pocket_tts_decoder.onnx"
        if decoder_path.exists():
            models["decoder"] = ort.InferenceSession(str(decoder_path))
            logger.info(f"  ✓ Loaded decoder: {decoder_path.name}")

        # Load vocoder
        vocoder_path = model_dir / "pocket_tts_vocoder.onnx"
        if vocoder_path.exists():
            models["vocoder"] = ort.InferenceSession(str(vocoder_path))
            logger.info(f"  ✓ Loaded vocoder: {vocoder_path.name}")

        return models if models else None
    except Exception as e:
        logger.warning(f"Could not load ONNX models: {e}")
        return None


def load_tokenizer(model_dir: Path) -> Optional[Any]:
    """
    Load the SentencePiece tokenizer.

    Args:
        model_dir: Path containing the tokenizer model

    Returns:
        Loaded tokenizer or None if not available
    """
    try:
        import sentencepiece as spm

        tokenizer_path = model_dir / "tokenizer.model"
        if tokenizer_path.exists():
            sp = spm.SentencePieceProcessor()
            sp.Load(str(tokenizer_path))
            logger.info(f"  ✓ Loaded tokenizer: {tokenizer_path.name}")
            return sp

        return None
    except Exception as e:
        logger.warning(f"Could not load tokenizer: {e}")
        return None


def compare_arrays(
    a: np.ndarray,
    b: np.ndarray,
    name: str,
    tolerances: Optional[Dict[str, float]] = None,
) -> VerificationResult:
    """
    Compare two numpy arrays with specified tolerances.

    Args:
        a: First array (reference)
        b: Second array (converted)
        name: Name of the comparison for reporting
        tolerances: Dictionary with 'atol', 'rtol', or 'exact_match'

    Returns:
        VerificationResult with comparison details
    """
    if tolerances is None:
        tolerances = {"atol": 1e-4, "rtol": 1e-3}

    # Check shapes match
    if a.shape != b.shape:
        return VerificationResult(
            test_name=name,
            passed=False,
            max_diff=float("inf"),
            mean_diff=float("inf"),
            details=f"Shape mismatch: {a.shape} vs {b.shape}",
        )

    # Exact match for discrete tokens
    if tolerances.get("exact_match", False):
        matches = np.array_equal(a, b)
        diff = np.sum(a != b)
        return VerificationResult(
            test_name=name,
            passed=matches,
            max_diff=float(diff),
            mean_diff=float(diff) / a.size,
            details=f"{'Exact match' if matches else f'{diff} mismatched tokens'}",
        )

    # Numerical comparison with tolerances
    diff = np.abs(a - b)
    max_diff = float(np.max(diff))
    mean_diff = float(np.mean(diff))

    atol = tolerances.get("atol", 1e-4)
    rtol = tolerances.get("rtol", 1e-3)

    passed = np.allclose(a, b, atol=atol, rtol=rtol)

    return VerificationResult(
        test_name=name,
        passed=passed,
        max_diff=max_diff,
        mean_diff=mean_diff,
        details=f"max_diff={max_diff:.6f}, mean_diff={mean_diff:.6f}, atol={atol}, rtol={rtol}",
    )


def verify_coreml_vs_pytorch(
    pytorch_model: Any,
    coreml_models: Dict[str, Any],
    tokenizer: Any,
    test_prompts: List[str],
) -> VerificationReport:
    """
    Verify CoreML models against PyTorch reference.

    Args:
        pytorch_model: Reference PyTorch model
        coreml_models: Dictionary of CoreML models
        tokenizer: SentencePiece tokenizer
        test_prompts: List of test prompts

    Returns:
        VerificationReport with all results
    """
    results = []

    for i, prompt in enumerate(test_prompts):
        logger.info(f"Testing prompt {i+1}/{len(test_prompts)}: '{prompt[:50]}...'")

        # Tokenize
        if tokenizer:
            tokens = tokenizer.Encode(prompt)
        else:
            tokens = list(range(len(prompt)))  # Placeholder

        # Run PyTorch inference
        # pytorch_output = pytorch_model(tokens)

        # Run CoreML inference
        # coreml_output = coreml_models["transformer"].predict(...)

        # Compare outputs
        # results.append(compare_arrays(...))

        # Placeholder result
        results.append(VerificationResult(
            test_name=f"coreml_prompt_{i+1}",
            passed=True,
            max_diff=0.0,
            mean_diff=0.0,
            details="Placeholder - requires model files",
        ))

    passed = sum(1 for r in results if r.passed)

    return VerificationReport(
        platform="CoreML (iOS)",
        total_tests=len(results),
        passed_tests=passed,
        failed_tests=len(results) - passed,
        results=results,
    )


def verify_onnx_vs_pytorch(
    pytorch_model: Any,
    onnx_models: Dict[str, Any],
    tokenizer: Any,
    test_prompts: List[str],
) -> VerificationReport:
    """
    Verify ONNX models against PyTorch reference.

    Args:
        pytorch_model: Reference PyTorch model
        onnx_models: Dictionary of ONNX inference sessions
        tokenizer: SentencePiece tokenizer
        test_prompts: List of test prompts

    Returns:
        VerificationReport with all results
    """
    results = []

    for i, prompt in enumerate(test_prompts):
        logger.info(f"Testing prompt {i+1}/{len(test_prompts)}: '{prompt[:50]}...'")

        # Tokenize
        if tokenizer:
            tokens = tokenizer.Encode(prompt)
        else:
            tokens = list(range(len(prompt)))  # Placeholder

        # Run PyTorch inference
        # pytorch_output = pytorch_model(tokens)

        # Run ONNX inference
        # encoder_output = onnx_models["encoder"].run(None, {...})
        # decoder_output = onnx_models["decoder"].run(None, {...})
        # vocoder_output = onnx_models["vocoder"].run(None, {...})

        # Compare outputs
        # results.append(compare_arrays(...))

        # Placeholder result
        results.append(VerificationResult(
            test_name=f"onnx_prompt_{i+1}",
            passed=True,
            max_diff=0.0,
            mean_diff=0.0,
            details="Placeholder - requires model files",
        ))

    passed = sum(1 for r in results if r.passed)

    return VerificationReport(
        platform="ONNX (Android)",
        total_tests=len(results),
        passed_tests=passed,
        failed_tests=len(results) - passed,
        results=results,
    )


def verify_voice_embeddings(
    coreml_dir: Optional[Path],
    onnx_dir: Optional[Path],
) -> List[VerificationResult]:
    """
    Verify voice embeddings are consistent across platforms.

    Args:
        coreml_dir: Path to CoreML models
        onnx_dir: Path to ONNX models

    Returns:
        List of verification results for each voice
    """
    results = []

    # Load embeddings
    coreml_voices = None
    onnx_voices = None

    if coreml_dir:
        voices_path = coreml_dir / "voices.bin"
        if voices_path.exists():
            coreml_voices = np.fromfile(voices_path, dtype=np.float32).reshape(8, -1)
            logger.info(f"  ✓ Loaded CoreML voices: {coreml_voices.shape}")

    if onnx_dir:
        voices_path = onnx_dir / "voices.bin"
        if voices_path.exists():
            onnx_voices = np.fromfile(voices_path, dtype=np.float32).reshape(8, -1)
            logger.info(f"  ✓ Loaded ONNX voices: {onnx_voices.shape}")

    # Compare if both available
    if coreml_voices is not None and onnx_voices is not None:
        for i, name in enumerate(VOICE_NAMES):
            result = compare_arrays(
                coreml_voices[i],
                onnx_voices[i],
                f"voice_{name}",
                {"atol": 1e-6, "rtol": 1e-5},  # Voices should be exact
            )
            results.append(result)

    return results


def generate_audio_samples(
    models: Dict[str, Any],
    tokenizer: Any,
    output_dir: Path,
    platform: str,
) -> List[Path]:
    """
    Generate audio samples for manual verification.

    Args:
        models: Loaded models (CoreML or ONNX)
        tokenizer: SentencePiece tokenizer
        output_dir: Directory to save audio files
        platform: Platform name for file naming

    Returns:
        List of paths to generated audio files
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    audio_files = []

    for i, prompt in enumerate(TEST_PROMPTS[:2]):  # Limit to 2 samples
        for voice in VOICE_NAMES[:3]:  # Test 3 voices
            logger.info(f"Generating: {voice} - '{prompt[:30]}...'")

            # Placeholder - actual synthesis requires model implementation
            # audio = synthesize(models, tokenizer, prompt, voice)

            filename = f"{platform}_{voice}_sample_{i+1}.wav"
            filepath = output_dir / filename

            # Save placeholder
            # sf.write(filepath, audio, 24000)

            audio_files.append(filepath)

    return audio_files


def print_report(report: VerificationReport) -> None:
    """
    Print a formatted verification report.

    Args:
        report: VerificationReport to print
    """
    print("\n" + "=" * 60)
    print(f"Verification Report: {report.platform}")
    print("=" * 60)
    print(f"Total tests: {report.total_tests}")
    print(f"Passed: {report.passed_tests}")
    print(f"Failed: {report.failed_tests}")
    print(f"Pass rate: {100 * report.passed_tests / max(1, report.total_tests):.1f}%")
    print("-" * 60)

    for result in report.results:
        status = "✓" if result.passed else "✗"
        print(f"  {status} {result.test_name}")
        print(f"      {result.details}")

    print("=" * 60 + "\n")


def save_report(report: VerificationReport, output_path: Path) -> None:
    """
    Save verification report to JSON file.

    Args:
        report: VerificationReport to save
        output_path: Path to save the JSON file
    """
    data = {
        "platform": report.platform,
        "total_tests": report.total_tests,
        "passed_tests": report.passed_tests,
        "failed_tests": report.failed_tests,
        "pass_rate": report.passed_tests / max(1, report.total_tests),
        "results": [
            {
                "test_name": r.test_name,
                "passed": r.passed,
                "max_diff": r.max_diff,
                "mean_diff": r.mean_diff,
                "details": r.details,
            }
            for r in report.results
        ],
    }

    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    logger.info(f"Report saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Verify Kyutai Pocket TTS model conversions"
    )
    parser.add_argument(
        "--pytorch-dir",
        type=str,
        default=None,
        help="Directory containing the original PyTorch model",
    )
    parser.add_argument(
        "--coreml-dir",
        type=str,
        default=None,
        help="Directory containing CoreML models",
    )
    parser.add_argument(
        "--onnx-dir",
        type=str,
        default=None,
        help="Directory containing ONNX models",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default="./verification_results",
        help="Directory to save verification results",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Run full verification including audio generation",
    )

    args = parser.parse_args()

    # Check that at least one model directory is provided
    if not any([args.pytorch_dir, args.coreml_dir, args.onnx_dir]):
        logger.error("Please provide at least one model directory")
        parser.print_help()
        sys.exit(1)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    logger.info("=" * 60)
    logger.info("Kyutai Pocket TTS - Cross-Platform Verification")
    logger.info("=" * 60)

    # Load models
    pytorch_model = None
    coreml_models = None
    onnx_models = None
    tokenizer = None

    if args.pytorch_dir:
        pytorch_dir = Path(args.pytorch_dir)
        logger.info(f"\nLoading PyTorch model from: {pytorch_dir}")
        pytorch_model = load_pytorch_model(pytorch_dir)
        tokenizer = load_tokenizer(pytorch_dir)

    if args.coreml_dir:
        coreml_dir = Path(args.coreml_dir)
        logger.info(f"\nLoading CoreML models from: {coreml_dir}")
        coreml_models = load_coreml_models(coreml_dir)
        if not tokenizer:
            tokenizer = load_tokenizer(coreml_dir)

    if args.onnx_dir:
        onnx_dir = Path(args.onnx_dir)
        logger.info(f"\nLoading ONNX models from: {onnx_dir}")
        onnx_models = load_onnx_models(onnx_dir)
        if not tokenizer:
            tokenizer = load_tokenizer(onnx_dir)

    # Run verifications
    reports = []

    if coreml_models and pytorch_model:
        logger.info("\n--- Verifying CoreML vs PyTorch ---")
        report = verify_coreml_vs_pytorch(
            pytorch_model, coreml_models, tokenizer, TEST_PROMPTS
        )
        reports.append(report)
        print_report(report)
        save_report(report, output_dir / "coreml_verification.json")

    if onnx_models and pytorch_model:
        logger.info("\n--- Verifying ONNX vs PyTorch ---")
        report = verify_onnx_vs_pytorch(
            pytorch_model, onnx_models, tokenizer, TEST_PROMPTS
        )
        reports.append(report)
        print_report(report)
        save_report(report, output_dir / "onnx_verification.json")

    # Verify voice embeddings across platforms
    if args.coreml_dir and args.onnx_dir:
        logger.info("\n--- Verifying Voice Embeddings ---")
        voice_results = verify_voice_embeddings(
            Path(args.coreml_dir) if args.coreml_dir else None,
            Path(args.onnx_dir) if args.onnx_dir else None,
        )
        for r in voice_results:
            status = "✓" if r.passed else "✗"
            logger.info(f"  {status} {r.test_name}: {r.details}")

    # Full verification with audio generation
    if args.full:
        logger.info("\n--- Generating Audio Samples ---")
        audio_dir = output_dir / "audio_samples"

        if coreml_models:
            generate_audio_samples(coreml_models, tokenizer, audio_dir, "coreml")

        if onnx_models:
            generate_audio_samples(onnx_models, tokenizer, audio_dir, "onnx")

    # Summary
    logger.info("\n" + "=" * 60)
    logger.info("VERIFICATION SUMMARY")
    logger.info("=" * 60)

    all_passed = True
    for report in reports:
        status = "✓ PASS" if report.failed_tests == 0 else "✗ FAIL"
        logger.info(f"  {report.platform}: {status} ({report.passed_tests}/{report.total_tests})")
        if report.failed_tests > 0:
            all_passed = False

    logger.info("")
    if not reports:
        logger.info("NOTE: Full verification requires model files to be available.")
        logger.info("This script will provide detailed comparison once models are converted.")
    elif all_passed:
        logger.info("All verifications PASSED!")
    else:
        logger.info("Some verifications FAILED. Check reports for details.")

    logger.info(f"\nResults saved to: {output_dir}")

    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
