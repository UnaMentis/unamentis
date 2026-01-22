#!/usr/bin/env python3
"""Convert SentencePiece tokenizer to JSON vocab format for Rust tokenizer."""

import json
import sys
from pathlib import Path

def convert_sentencepiece_to_json(sp_model_path: Path, output_path: Path):
    """Convert SentencePiece model to JSON vocab format.

    The SentencePiece model is a protobuf file. We parse it to extract
    the vocabulary mapping (token -> id).
    """
    try:
        import sentencepiece as spm

        # Load SentencePiece model
        sp = spm.SentencePieceProcessor()
        sp.Load(str(sp_model_path))

        # Extract vocabulary
        vocab = {}
        vocab_size = sp.GetPieceSize()

        for i in range(vocab_size):
            piece = sp.IdToPiece(i)
            vocab[piece] = i

        # Write JSON
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(vocab, f, ensure_ascii=False, indent=2)

        print(f"Converted {vocab_size} tokens to {output_path}")
        return True

    except ImportError:
        print("sentencepiece not installed, using protobuf fallback...")
        return convert_protobuf_fallback(sp_model_path, output_path)

def convert_protobuf_fallback(sp_model_path: Path, output_path: Path):
    """Fallback: Parse SentencePiece protobuf directly."""
    try:
        # Try to parse the protobuf format directly
        # SentencePiece uses a custom protobuf schema
        import struct

        vocab = {}

        with open(sp_model_path, 'rb') as f:
            data = f.read()

        # SentencePiece protobuf format:
        # Each piece is: field_tag(1 byte) + length + piece_data
        # Piece data contains: piece string and score

        i = 0
        token_id = 0

        while i < len(data):
            # Field tag
            if i >= len(data):
                break

            tag = data[i]
            i += 1

            # Check for piece field (tag 0x0a = field 1, wire type 2 = length-delimited)
            if tag == 0x0a:
                # Read length (varint)
                length = 0
                shift = 0
                while i < len(data):
                    b = data[i]
                    i += 1
                    length |= (b & 0x7f) << shift
                    if (b & 0x80) == 0:
                        break
                    shift += 7

                # Read the piece submessage
                piece_end = i + length
                piece_text = None

                while i < piece_end:
                    sub_tag = data[i]
                    i += 1

                    # String field (piece text) - tag 0x0a
                    if sub_tag == 0x0a:
                        str_len = 0
                        shift = 0
                        while i < len(data):
                            b = data[i]
                            i += 1
                            str_len |= (b & 0x7f) << shift
                            if (b & 0x80) == 0:
                                break
                            shift += 7

                        piece_text = data[i:i+str_len].decode('utf-8', errors='replace')
                        i += str_len

                    # Float field (score) - tag 0x15
                    elif sub_tag == 0x15:
                        i += 4  # Skip 4-byte float

                    # Int field (type) - tag 0x18
                    elif sub_tag == 0x18:
                        while i < len(data) and (data[i] & 0x80):
                            i += 1
                        i += 1

                    else:
                        # Skip unknown field
                        break

                if piece_text is not None:
                    vocab[piece_text] = token_id
                    token_id += 1

                i = piece_end
            else:
                # Skip unknown top-level fields
                wire_type = tag & 0x07
                if wire_type == 0:  # Varint
                    while i < len(data) and (data[i] & 0x80):
                        i += 1
                    i += 1
                elif wire_type == 1:  # 64-bit
                    i += 8
                elif wire_type == 2:  # Length-delimited
                    length = 0
                    shift = 0
                    while i < len(data):
                        b = data[i]
                        i += 1
                        length |= (b & 0x7f) << shift
                        if (b & 0x80) == 0:
                            break
                        shift += 7
                    i += length
                elif wire_type == 5:  # 32-bit
                    i += 4

        if len(vocab) > 0:
            with open(output_path, 'w', encoding='utf-8') as f:
                json.dump(vocab, f, ensure_ascii=False, indent=2)

            print(f"Converted {len(vocab)} tokens to {output_path}")
            return True
        else:
            print("Failed to parse any tokens from protobuf")
            return False

    except Exception as e:
        print(f"Protobuf fallback failed: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        model_dir = Path("/Users/ramerman/dev/unamentis/models/kyutai-pocket-ios")
    else:
        model_dir = Path(sys.argv[1])

    sp_model = model_dir / "tokenizer.model"
    json_output = model_dir / "tokenizer.json"

    if not sp_model.exists():
        print(f"Error: {sp_model} not found")
        sys.exit(1)

    success = convert_sentencepiece_to_json(sp_model, json_output)

    if success:
        print(f"\nSuccess! JSON vocab written to: {json_output}")

        # Show sample
        with open(json_output, 'r') as f:
            vocab = json.load(f)

        print(f"\nVocab size: {len(vocab)}")
        print("Sample tokens:")
        for token, idx in list(vocab.items())[:10]:
            print(f"  {repr(token)}: {idx}")
    else:
        print("\nConversion failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
