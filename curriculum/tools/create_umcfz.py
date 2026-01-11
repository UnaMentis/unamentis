#!/usr/bin/env python3
"""
UMCF Packaging Tool

Creates .umcfz compressed packages from .umcf files and optional image assets.

Usage:
    python create_umcfz.py input.umcf output.umcfz [--assets assets_dir]

Example:
    python create_umcfz.py color-theory.umcf color-theory.umcfz --assets ./images
"""

import argparse
import base64
import gzip
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def get_mime_type(filename: str) -> str:
    """Get MIME type from file extension."""
    ext = Path(filename).suffix.lower()
    mime_types = {
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.gif': 'image/gif',
        '.svg': 'image/svg+xml',
        '.webp': 'image/webp',
    }
    return mime_types.get(ext, 'application/octet-stream')


def load_assets(assets_dir: str) -> dict:
    """Load all image assets from a directory."""
    assets = {}
    assets_path = Path(assets_dir)

    if not assets_path.exists():
        print(f"Warning: Assets directory '{assets_dir}' does not exist")
        return assets

    image_extensions = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'}

    for file_path in assets_path.rglob('*'):
        if file_path.is_file() and file_path.suffix.lower() in image_extensions:
            asset_id = file_path.stem  # Use filename without extension as ID
            with open(file_path, 'rb') as f:
                binary_data = f.read()
            assets[asset_id] = base64.b64encode(binary_data).decode('utf-8')
            print(f"  Added asset: {asset_id} ({len(binary_data)} bytes)")

    return assets


def create_umcfz(input_file: str, output_file: str, assets_dir: str = None):
    """Create a .umcfz package from a .umcf file and optional assets."""

    # Load the UMCF document
    print(f"Loading UMCF document: {input_file}")
    with open(input_file, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    # Load assets if directory provided
    assets = {}
    if assets_dir:
        print(f"Loading assets from: {assets_dir}")
        assets = load_assets(assets_dir)
        print(f"  Loaded {len(assets)} assets")

    # Create metadata
    metadata = {
        "packageVersion": "1.0.0",
        "createdAt": datetime.utcnow().isoformat() + "Z",
        "createdBy": "UMCF Packaging Tool",
        "assetCount": len(assets)
    }

    # Create the archive structure
    archive = {
        "manifest": manifest,
        "assets": assets,
        "metadata": metadata
    }

    # Serialize to JSON
    json_data = json.dumps(archive, separators=(',', ':'))  # Compact JSON

    # Compress with gzip
    print(f"Compressing package...")
    compressed_data = gzip.compress(json_data.encode('utf-8'))

    # Write output file
    print(f"Writing output: {output_file}")
    with open(output_file, 'wb') as f:
        f.write(compressed_data)

    # Print summary
    original_size = len(json_data)
    compressed_size = len(compressed_data)
    ratio = (1 - compressed_size / original_size) * 100

    print(f"\nPackage created successfully!")
    print(f"  Original size:   {original_size:,} bytes")
    print(f"  Compressed size: {compressed_size:,} bytes")
    print(f"  Compression:     {ratio:.1f}%")
    print(f"  Assets:          {len(assets)}")


def create_simple_umcfz(input_file: str, output_file: str):
    """Create a simple .umcfz package (just compressed JSON, no assets)."""

    print(f"Loading UMCF document: {input_file}")
    with open(input_file, 'r', encoding='utf-8') as f:
        document = json.load(f)

    # Serialize to JSON
    json_data = json.dumps(document, separators=(',', ':'))

    # Compress with gzip
    print(f"Compressing...")
    compressed_data = gzip.compress(json_data.encode('utf-8'))

    # Write output file
    print(f"Writing output: {output_file}")
    with open(output_file, 'wb') as f:
        f.write(compressed_data)

    print(f"\nSimple package created!")
    print(f"  Compressed size: {len(compressed_data):,} bytes")


def main():
    parser = argparse.ArgumentParser(
        description='Create .umcfz packages from UMCF files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create simple compressed package (no assets):
  python create_umcfz.py curriculum.umcf curriculum.umcfz

  # Create package with embedded assets:
  python create_umcfz.py curriculum.umcf curriculum.umcfz --assets ./images

  # Simple mode (just compress, no archive structure):
  python create_umcfz.py curriculum.umcf curriculum.umcfz --simple
"""
    )

    parser.add_argument('input', help='Input .umcf file')
    parser.add_argument('output', help='Output .umcfz file')
    parser.add_argument('--assets', '-a', help='Directory containing image assets')
    parser.add_argument('--simple', '-s', action='store_true',
                       help='Create simple compressed file (no archive structure)')

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"Error: Input file '{args.input}' not found")
        sys.exit(1)

    if args.simple:
        create_simple_umcfz(args.input, args.output)
    else:
        create_umcfz(args.input, args.output, args.assets)


if __name__ == '__main__':
    main()
