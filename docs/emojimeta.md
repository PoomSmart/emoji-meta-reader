# emojimeta.dat Format

Binary file used by `CoreEmoji.framework` to store per-emoji metadata — ordering, flags, string offsets, and descriptions. Found at:

```
CoreEmoji.framework/emojimeta.dat
```

---

## Format Variants

There are four format variants, distinguished by emoji count ranges (modes 0–2) or a special header encoding (mode 3):

| Mode | iOS Versions | Entry size | Entry format |
|------|-------------|-----------|--------------|
| 0 | 10.1.1 | 10 bytes | 5 × `uint16_t` |
| 1 | 10.2 – 12.0 | 14 bytes | 7 × `uint16_t` |
| 2 | 12.1 – 16.7 | 16 bytes | 4 × `uint32_t` |
| 3 | 17.0+ | 16 bytes | 4 × `uint32_t` + 2-byte header shift |

---

## File Layout

### Modes 0, 1, 2

```
Offset  Size   Field
──────  ─────  ─────────────────────────────────────
0x00    2      count          — total number of emojis (uint16_t)
0x02    2      tw_flag_idx    — index of the Taiwan flag emoji (uint16_t)
0x04    4      file_size      — total file size in bytes (uint32_t)
0x08    …      entries[]      — array of per-emoji metadata records
                                (each record is 10, 14, or 16 bytes depending on mode)
```

Mode is inferred from `count`:
- `count >= 2937` → mode 2
- `count >= 2538` → mode 1
- otherwise → mode 0

### Mode 3

```
Offset  Size   Field
──────  ─────  ─────────────────────────────────────
0x00    4      count32        — emoji count stored in one 16-bit half; the other half is 0
                                • if count32[15:0] == 0 → count = count32[31:16]
                                • if count32[31:16] == 0 → count = count32[15:0]
0x04    2      tw_flag_idx    — index of the Taiwan flag emoji (uint16_t)
0x06    4      file_size      — total file size in bytes (uint32_t)
0x0A    …      entries[]      — per-emoji metadata records (each 16 bytes)
```

> The 2-byte offset shift (`0x0A` vs `0x08`) is handled internally; `emdreader` accounts for it automatically.

---

## Entry Format

### Mode 0 — 5 × uint16_t (10 bytes)

| Word | Field | Notes |
|------|-------|-------|
| [0] | `flags` | See [Metadata Flags](#metadata-flags) |
| [1] | `base_index` | 1-based index of the skin-tone base emoji; 0 = this is the base |
| [2] | `d2` | Purpose unclear; possibly a sort/category hint |
| [3] | `emoji_offset` | File offset to the null-terminated UTF-8 emoji string |
| [4] | `desc_offset` | File offset to the null-terminated ASCII description string |

### Mode 1 — 7 × uint16_t (14 bytes)

| Word | Field | Notes |
|------|-------|-------|
| [0] | `flags` | See [Metadata Flags](#metadata-flags) |
| [1] | `base_index_lo` | Low 16 bits of base index |
| [2] | `d2` | High 16 bits were packed here when converting from mode 2 |
| [3] | `emoji_offset_lo` | Low 16 bits of emoji string file offset |
| [4] | `emoji_offset_hi` | High 16 bits; `emoji_ptr = [4]<<16 \| [3]` |
| [5] | `desc_offset_lo` | Low 16 bits of description offset |
| [6] | `desc_offset_hi` | High 16 bits; `desc_ptr = [6]<<16 \| [5]` |

### Modes 2 & 3 — 4 × uint32_t (16 bytes)

| Dword | Field | Notes |
|-------|-------|-------|
| [0] | `flags` | See [Metadata Flags](#metadata-flags) (full 32-bit in modes 2/3) |
| [1] | `d1` | `d1[15:0]` = `base_index`; `d1[31:16]` = `d2` (category/sort field) |
| [2] | `emoji_offset` | File offset to the null-terminated UTF-8 emoji string |
| [3] | `desc_offset` | File offset to the null-terminated ASCII description string |

Offsets in mode 3 are 2 bytes larger than their effective value due to the header shift; `emdreader` adjusts by subtracting the shift on conversion.

---

## Metadata Flags

These are flags in the `flags` field (dword [0] / word [0]):

| Flag | Value | Description |
|------|-------|-------------|
| `FLAG_STYLE_2` | `0x10` | Presentation style 2 (text vs emoji selector) |
| `FLAG_STYLE_1` | `0x20` | Presentation style 1 |
| `FLAG_SKIN` | `0x40` | Emoji has skin-tone variants |
| `FLAG_COMMON` | `0x80` | Commonly-used emoji (shown prominently) |
| `FLAG_HAIR` | `0x100` | Emoji has hair-style variants |
| `FLAG_FEMALE_LEGACY` | `0x200` | Female variant (modes 0, 1) |
| `FLAG_MALE_LEGACY` | `0x100` | Male variant (modes 0, 1) — shares bit with `FLAG_HAIR` |
| `FLAG_MALE_MODERN` | `0x10000` | Male variant (modes 2, 3) |
| `FLAG_FEMALE_MODERN` | `0x20000` | Female variant (modes 2, 3) |

> `FLAG_HAIR` and `FLAG_MALE_LEGACY` share `0x100` in modes 0/1. The gender flags were split and moved to the upper word in modes 2/3 to resolve this conflict.

### Derived Fields

**Skin tone** (only meaningful when `base_index != 0`):
- Modes 0, 1: `(flags >> 12) & 0xF`
- Modes 2, 3: `(flags >> 20) & 0xF`

**Hair style**: `flags >> 24`

**Presentation style**:
- Returns `1` if `FLAG_STYLE_1` set
- Returns `2` if `FLAG_STYLE_2` set
- Returns `0` otherwise

---

## String Data

Both the emoji characters and their descriptions are stored as null-terminated strings in the same file. Offsets from the `emoji_offset` and `desc_offset` fields are absolute file offsets (byte positions from the start of the file).

- **Emoji string**: UTF-8 encoded, includes ZWJ sequences and variation selectors
- **Description string**: uppercase ASCII, e.g. `GRINNING FACE`

---

## Example Output

```
[0x1  ] 😀  :  00000080 00bf0000 | [0x0  ]  [0x102ea]  [0x1cae4]
    (skin: 0-0, base-idx: 0, hair: 0-0, gender: -, style: 0, common: 1, desc: GRINNING FACE)
```

Fields:
- `[0x1]` — 1-based index in the metadata array
- `😀` — decoded UTF-8 emoji
- `00000080 00bf0000` — raw `flags` and `d1` dwords
- `[0x0]` — resolved `base_index`
- `[0x102ea]` — `emoji_offset`
- `[0x1cae4]` — `desc_offset`
