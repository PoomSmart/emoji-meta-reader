# Emoji Meta Reader

A tool for reading and converting iOS emoji binary data files from `CoreEmoji.framework`.

## Overview

iOS stores emoji data in two kinds of binary `.dat` files:

- **[emojimeta.dat](docs/emojimeta.md)** — per-emoji metadata (ordering, flags, descriptions). Format has changed across iOS versions; `emdreader` can read and convert between all variants.
- **[FindReplace.dat / CharacterPicker.dat](docs/emoji-keyword-trie.md)** — keyword-to-emoji search index. iOS ≤16 uses a CFBurstTrie; iOS 17+ uses a Marisa LOUDS trie. `emdreader` auto-detects and parses both variants.

## File Format Documentation

| File | Description |
|------|-------------|
| [docs/emojimeta.md](docs/emojimeta.md) | `emojimeta.dat` binary format (modes 0–3) |
| [docs/emoji-keyword-trie.md](docs/emoji-keyword-trie.md) | `FindReplace.dat` / `CharacterPicker.dat` / `LocaleData-en.dat` — iOS ≤16 (CFBurstTrie) and iOS 17+ (Marisa) |

## Supported emojimeta Variants

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

### Reading Metadata (emojimeta.dat)

```bash
./bin/emdreader -i /path/to/emojimeta.dat
```

### Reading a FindReplace / Keyword-Search Index

`emdreader` auto-detects FindReplace files by their magic number:

```bash
./bin/emdreader -i FindReplace-en.dat

# Find all payload entries that reference emoji index 0x1
./bin/emdreader -i FindReplace-en.dat | grep '0x1[,\]]'
```

### Converting emojimeta Between Formats

```bash
./bin/emdreader -i input.dat -e <mode> -o output.dat

# Example: Convert iOS 17+ format to iOS 12.1-16.7 format
./bin/emdreader -i emojimeta.dat -e 2 -o emojimeta_2.dat
```

### Filtering emojimeta Output

```bash
# Filter by metadata flags (hex)
./bin/emdreader -i emojimeta.dat -f 40   # Show only emojis with skin tone variants
./bin/emdreader -i emojimeta.dat -f 80   # Show only "common" emojis
```

### Options

| Option | Description |
|--------|-------------|
| `-i <path>` | Input file (required) — emojimeta.dat or FindReplace.dat |
| `-o <path>` | Output file for conversion |
| `-e <mode>` | Export mode (0-3, emojimeta only) |
| `-f <hex>` | Filter by metadata flags (emojimeta only) |
| `-h` | Show help |

## emojimeta Output Format

```
[0x1  ] 😀  :  00000080 00bf0000 | [0x0  ]  [0xf72a]  [0x1ad3e]  (skin: 0-0, base-idx: 0, hair: 0-0, gender: -, style: 0, common: 1, desc: GRINNING FACE)
```

Fields:
- **Index**: Emoji position in the metadata
- **Emoji**: The actual emoji character
- **Flags**: Raw metadata flags
- **Positions**: String and description offsets
- **Properties**: Parsed attributes (skin tone, hair, gender, etc.)

## FindReplace Output Format

```
Format:             FindReplace (trie+index)
Version:            1
Flags:              0x0000
Trie blob size:     0x12428 (74792 bytes)
Index array count:  5791 entries
Marisa trie size:   0x9A70 (39536 bytes)
Keyword count:      8813

--- Keyword Payload Table (8813 entries) ---
[    0] start=0x00000 count=3   -> [0x12, 0x34, 0x56]
```

Payload indices correspond to the `[idx]` column in `emdreader` emojimeta output.

## Batch Conversion

Use `generator.sh` to convert a metadata file to all format variants:

```bash
./generator.sh /path/to/emojimeta.dat
```

This generates `emojimeta_0.dat`, `emojimeta_1.dat`, `emojimeta_2.dat` and copies them to the EmojiPort resources directory.

## Metadata Flags

See [docs/emojimeta.md](docs/emojimeta.md#metadata-flags) for the full flag reference.

## License

See [LICENSE](LICENSE) for details.
