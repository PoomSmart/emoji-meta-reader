# Emoji Meta Reader

A tool for reading and converting iOS emoji metadata files (`emojimeta.dat`) between different iOS version formats.

## Overview

iOS stores emoji metadata in binary `.dat` files within the CoreEmoji framework. The format has changed across iOS versions, and this tool can:

- **Read** emoji metadata from any supported format and display parsed information
- **Convert** metadata between different iOS version formats

## Supported Formats

| Mode | iOS Version | Notes |
|------|-------------|-------|
| 3 | iOS 17.0+ | Latest format with 4-byte header offset |
| 2 | iOS 12.1 - 16.7 | Modern format with 32-bit metadata |
| 1 | iOS 10.2 - 12.0 | Legacy format with 16-bit metadata |
| 0 | iOS 10.1.1 | Oldest format (max 3206 emojis) |

## Building

Requires [Theos](https://theos.dev/) build system.

```bash
make
```

The compiled binary will be placed in `bin/emdreader`.

## Usage

### Reading Metadata

```bash
# Display emoji metadata from a .dat file
./bin/emdreader -i /path/to/emojimeta.dat
```

### Converting Between Formats

```bash
# Convert to a specific format
./bin/emdreader -i input.dat -e <mode> -o output.dat

# Example: Convert iOS 17+ format to iOS 12.1-16.7 format
./bin/emdreader -i emojimeta.dat -e 2 -o emojimeta_2.dat
```

### Filtering Output

```bash
# Filter by metadata flags (hex)
./bin/emdreader -i emojimeta.dat -f 40   # Show only emojis with skin tone variants
./bin/emdreader -i emojimeta.dat -f 80   # Show only "common" emojis
```

### Options

| Option | Description |
|--------|-------------|
| `-i <path>` | Input metadata file (required) |
| `-o <path>` | Output file for conversion |
| `-e <mode>` | Export mode (0-3, see formats above) |
| `-f <hex>` | Filter by metadata flags |
| `-h` | Show help |

## Output Format

The tool outputs parsed emoji information:

```
[0x1  ] 😀  :  00000080 00bf0000 | [0x0  ]  [0xf72a]  [0x1ad3e]  (skin: 0-0, base-idx: 0, hair: 0-0, gender: -, style: 0, common: 1, desc: GRINNING FACE)
```

Fields:
- **Index**: Emoji position in the metadata
- **Emoji**: The actual emoji character
- **Flags**: Raw metadata flags
- **Positions**: String and description offsets
- **Properties**: Parsed attributes (skin tone, hair, gender, etc.)

## Batch Conversion

Use `generator.sh` to convert a metadata file to all format variants:

```bash
./generator.sh /path/to/emojimeta.dat
```

This generates `emojimeta_0.dat`, `emojimeta_1.dat`, `emojimeta_2.dat` and copies them to the EmojiPort resources directory.

## Metadata Flags

| Flag | Meaning |
|------|---------|
| `0x40` | Has skin tone variants |
| `0x80` | Common emoji |
| `0x100` | Has hair style variants |
| `0x10000` | Male variant (modern) |
| `0x20000` | Female variant (modern) |
| `0x10` | Presentation style 2 |
| `0x20` | Presentation style 1 |

## License

See [LICENSE](LICENSE) for details.
