# UMCF File Format Specification

**Version 1.0.0**

This document specifies the file formats for storing and exchanging UMCF (Una Mentis Curriculum Format) documents.

## File Extensions

UMCF supports two file formats:

| Extension | Format | Description |
|-----------|--------|-------------|
| `.umcf` | Raw JSON | Uncompressed JSON file, human-readable |
| `.umcfz` | Compressed Package | Gzip-compressed archive containing JSON and assets |

## Raw Format (.umcf)

The `.umcf` format is a plain JSON file containing the UMCF document structure.

### Characteristics

- **MIME Type**: `application/vnd.umcf+json`
- **Encoding**: UTF-8
- **Structure**: Single JSON object following the UMCF schema
- **Use Case**: Development, debugging, version control

### Example

```json
{
  "umcf": "1.0.0",
  "id": { "catalog": "UUID", "value": "550e8400-e29b-41d4-a716-446655440000" },
  "title": "Introduction to Machine Learning",
  "description": "A beginner-friendly course on ML fundamentals.",
  "version": { "number": "1.0.0", "date": "2025-01-10T00:00:00Z" },
  "content": [...]
}
```

### Advantages

- Human-readable and editable
- Git-friendly (text-based diffs)
- Easy to validate and debug
- No additional tooling required to inspect

### Limitations

- No embedded binary assets (images must be URLs or external paths)
- Larger file size for complex curricula
- Not suitable for distribution with bundled media

## Compressed Package Format (.umcfz)

The `.umcfz` format is a gzip-compressed archive optimized for interchange and storage.

### Characteristics

- **MIME Type**: `application/vnd.umcf+gzip`
- **Compression**: Gzip (RFC 1952)
- **Structure**: Compressed archive containing manifest and assets
- **Use Case**: Distribution, offline use, sharing

### Archive Structure

When decompressed, a `.umcfz` file contains:

```
curriculum.umcfz (gzipped)
  └── curriculum/
      ├── manifest.json          # UMCF document with asset references
      ├── assets/                # Binary assets directory
      │   ├── img_001.png
      │   ├── img_002.jpg
      │   └── diagram_001.svg
      └── metadata.json          # Optional package metadata
```

### manifest.json

The `manifest.json` file is the UMCF document with asset paths relative to the archive:

```json
{
  "umcf": "1.0.0",
  "id": { "catalog": "UUID", "value": "550e8400-e29b-41d4-a716-446655440000" },
  "title": "Introduction to Machine Learning",
  "content": [
    {
      "id": { "value": "topic-1" },
      "title": "What is Machine Learning?",
      "type": "topic",
      "media": {
        "embedded": [
          {
            "id": "ml-overview-diagram",
            "type": "diagram",
            "localPath": "assets/ml_overview.png",
            "alt": "Machine learning pipeline diagram"
          }
        ]
      }
    }
  ]
}
```

### metadata.json (Optional)

Package metadata for distribution:

```json
{
  "packageVersion": "1.0.0",
  "createdAt": "2025-01-10T12:00:00Z",
  "createdBy": "UnaMentis Curriculum Builder",
  "checksum": "sha256:abc123...",
  "totalSize": 1048576,
  "assetCount": 5
}
```

### Advantages

- Self-contained with all assets bundled
- Significantly smaller file size (typically 60-80% compression)
- Single file for easy sharing and distribution
- Offline-ready with all media included
- Integrity verification via checksum

### Limitations

- Not human-readable without extraction
- Requires tooling to create and inspect
- Binary format not suitable for version control diffs

## Format Selection Guide

| Scenario | Recommended Format |
|----------|-------------------|
| Development and editing | `.umcf` |
| Version control (Git) | `.umcf` |
| Sharing with others | `.umcfz` |
| Offline distribution | `.umcfz` |
| Curriculum with images | `.umcfz` |
| API responses | `.umcf` (JSON) |
| Mobile app import | `.umcfz` |
| Schema validation | `.umcf` |

## Implementation Notes

### Reading .umcf Files

```swift
// Swift
let data = try Data(contentsOf: url)
let document = try JSONDecoder().decode(UMCFDocument.self, from: data)
```

### Reading .umcfz Files

```swift
// Swift
let compressedData = try Data(contentsOf: url)
let decompressedData = try (compressedData as NSData).decompressed(using: .zlib)

// For archives with assets, extract to temp directory first
let tempDir = FileManager.default.temporaryDirectory
// Extract archive...
let manifestURL = tempDir.appendingPathComponent("manifest.json")
let document = try JSONDecoder().decode(UMCFDocument.self, from: Data(contentsOf: manifestURL))
```

### Writing .umcfz Files

```swift
// Swift
let jsonData = try JSONEncoder().encode(document)
let compressedData = try (jsonData as NSData).compressed(using: .zlib)
try compressedData.write(to: outputURL)
```

## Versioning

The file format version is indicated by:

1. The `umcf` field in the JSON document (schema version)
2. The `packageVersion` field in metadata.json (package format version)

Both follow semantic versioning (MAJOR.MINOR.PATCH).

## Security Considerations

When importing `.umcfz` files:

1. **Validate checksum** if provided in metadata
2. **Scan for path traversal** in asset paths (e.g., `../../../etc/passwd`)
3. **Limit extraction size** to prevent zip bombs
4. **Verify content types** of embedded assets
5. **Sanitize file names** before extraction

## Future Extensions

- Encryption support for protected content
- Digital signatures for authenticity
- Delta updates for incremental sync
- Multi-language bundles in single package
