# Emoji Keyword Search Index Format

Binary `.dat` files used by `CoreEmoji.framework` to map UTF-8 search keywords to emoji indices. Loaded by `CEM::EmojiSearchTrie` when the emoji keyboard suggests emojis while typing (e.g. "smile" → 😀).

## File Names

This format is shared across several files:

| File | Purpose |
|------|---------|
| `FindReplace-en.dat` / `LocaleData-en.dat` | English keyword→emoji for the text replacement / prediction keyboard |
| `CharacterPicker.dat` (per-locale in `*.lproj/`) | Emoji picker keyboard keyword index |
| `StaticAssets/ja.dat` | Japanese keyword index (shared across `ja` locales) |
| `StaticAssets/zh.shared.dat` | Chinese/Cantonese keyword index (`zh`, `yue`) |

Locale selection order (from `createEmojiSearchTrie`):

| Language | Tries in order |
|----------|---------------|
| `ja` | `StaticAssets/ja.dat` |
| `zh`, `yue` | `StaticAssets/zh.shared.dat` |
| `en`, `en_US` | `LocaleData-en.dat` |
| other locales | `LocaleData-<locale>.dat` → `FindReplace.dat` → `CharacterPicker.dat` → `LocaleData-en.dat` (fallback) |

---

## Format Variants

The **file header and index array are identical across all iOS versions**. Only the trie blob format changed:

| iOS Version | Trie Engine | Detection |
|-------------|-------------|-----------|
| ≤ 16 | **CFBurstTrie** (CoreFoundation private API) | `blob[0..3]` as `uint32` > `trie_blob_size − 4` |
| 17+ | **Marisa LOUDS trie** ([github.com/s-yata/marisa-trie](https://github.com/s-yata/marisa-trie)) | `blob[0..3]` as `uint32` ≤ `trie_blob_size − 4` |

---

## Overview

Both variants store keyword→emoji mappings in a compact trie, backed by a shared flat index array of emoji indices. The trie maps each keyword to a `(start, count)` payload that slices the index array.

---

## File Layout

```
Offset                      Size                       Field
──────                      ────                       ─────────────────────────────────
0x00                        16 bytes                   File Header
0x10                        trie_blob_size bytes        Trie Blob  (CFBurstTrie OR Marisa)
0x10 + trie_blob_size       index_array_count × 2      Index Array
```

---

## 1. File Header (16 bytes)

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| `0x00` | `uint32` | `magic` | Must be `0x3FA8BDD1` |
| `0x04` | `uint16` | `version` | Must be `1` |
| `0x06` | `uint16` | `flags` | See [Flags](#flags) |
| `0x08` | `uint32` | `trie_blob_size` | Byte length of the Trie Blob section |
| `0x0C` | `uint32` | `index_array_count` | Total `uint16_t` entries in the Index Array |

### Flags

| Bit | Meaning |
|-----|---------|
| `0` | **Null-terminated lists** — index spans are terminated by a `0` entry rather than using the count encoded in the payload ref |
| `1` | **Secondary trie** — a second Marisa trie follows the primary, used for locale-specific suffix matching (e.g. country-code disambiguation) |

---

## 2. Trie Blob

### 2a. CFBurstTrie variant (iOS ≤16)

The entire trie blob is a serialized `CFBurstTrieRef` as written by Apple's private `CFBurstTrie` API (CoreFoundation). It stores keyword strings and their payload values internally.

**Detection:** `*(uint32_t*)blob + 4 > trie_blob_size`

**Reading:** Use `CFBurstTrieCreateFromMapBytes(blob, trie_blob_size)` from CoreFoundation. Enumerate all keyword→payload pairs with `CFBurstTrieTraverseFromCursor`. The payload for each keyword is a packed `uint32_t` in the same format as Marisa (see [Payload Encoding](#payload-encoding)).

```c
CFBurstTrieRef   trie = CFBurstTrieCreateFromMapBytes(blob, size);
CFBurstTrieCursorRef c = CFBurstTrieCreateCursorForBytes(trie, NULL, 0);
CFBurstTrieSetCursorForBytes(trie, c, NULL, 0);       // position at root
CFBurstTrieTraverseFromCursor(c, ctx, callback);      // enumerate all entries
// callback signature: (void *ctx, const uint8_t *key, uint32_t keyLen,
//                      uint32_t payload, uint8_t *flags)
```

### 2b. Marisa LOUDS variant (iOS 17+)

```
Blob offset        Size                    Field
──────────         ────                    ──────────────────────────────────────────
0x00               uint32                  inner_marisa_size  (byte length of Marisa data)
0x04               inner_marisa_size       Marisa LOUDS trie  (starts with "We love Marisa.")
0x04+inner_size    payload_count × uint32  Payload Table
```

Where:
```
payload_count = (trie_blob_size − inner_marisa_size − 4) / 4
```

Each Marisa key has a 0-based key ID assigned at build time (insertion order). The Payload Table is indexed by key ID; entry `i` holds the `payload_ref` for key ID `i`.

**Key strings are embedded in the Marisa trie blob.** They cannot be enumerated without linking `libmarisa`. `emdreader` therefore displays payload entries by key ID rather than keyword string for this variant.

---

## Payload Encoding

Both CFBurstTrie and Marisa store the same packed `uint32_t` payload per keyword:

| Bits | Field | Description |
|------|-------|-------------|
| 0–21 | `start` | Base offset (in `uint16_t` units) into the Index Array |
| 22–31 | `count` | Number of consecutive `uint16_t` entries (max 1023) |

**Decoding:**
```c
uint32_t start = payload_ref & 0x3FFFFF;
uint32_t count = (payload_ref >> 22) & 0x3FF;
// emoji indices: index_array[start .. start+count-1]
```

When `flags & 1` (null-terminated mode), `count` is ignored; the index array is walked from `start` forward until a `0` entry.

---

## 3. Index Array

A flat `uint16_t[index_array_count]` following the Trie Blob. Each value is a **1-based emoji index** corresponding to the `[idx]` column in `emdreader`'s `emojimeta.dat` output.

Multiple keywords may reference overlapping windows of this array (payload `start` ranges can overlap).

---

## Lookup Flow

```
Input word (UTF-8)
  ↓
Trie lookup (CFBurstTrie or Marisa)  →  payload_ref (uint32)
  ↓
start = payload_ref & 0x3FFFFF
count = (payload_ref >> 22) & 0x3FF
  ↓
index_array[start .. start+count-1]  →  emoji indices (uint16_t[], 1-based)
  ↓
emojimeta.dat[index]  →  emoji character + metadata
```

---

## Format Conversion

Conversion between iOS ≤16 (CFBurstTrie) and iOS 17+ (Marisa) formats is **not supported** by `emdreader` because:

- **CFBurstTrie → Marisa**: requires building a new Marisa trie, which needs `libmarisa` (not linked by this tool)
- **Marisa → CFBurstTrie**: requires enumerating Marisa keys (needs `libmarisa`) and serializing a new CFBurstTrie

The **Index Array is identical** in both formats and requires no conversion.

---

## Concrete Examples

### iOS 16.4  —  `FindReplace-en.dat`

| Field | Value |
|-------|-------|
| Magic | `0x3FA8BDD1` |
| Trie engine | CFBurstTrie (iOS ≤16) |
| Flags | `0x0000` |
| `trie_blob_size` | `0x17EB4` (97,972 bytes) |
| `index_array_count` | `0x303A` (12,346 entries) |
| Keyword count | 7,901 |
| Total file size | 122,680 bytes |

### iOS 26.4  —  `LocaleData-en.dat`

| Field | Value |
|-------|-------|
| Magic | `0x3FA8BDD1` |
| Trie engine | Marisa LOUDS (iOS 17+) |
| Flags | `0x0002` (secondary trie) |
| `trie_blob_size` | `0x219C0` (137,664 bytes) |
| `index_array_count` | `0x4B3E` (19,326 entries) |
| `inner_marisa_size` | `0x11890` (71,824 bytes) |
| Keyword count | 16,459 |
| Total file size | 176,344 bytes |

---

## emdreader Usage

`emdreader` auto-detects both variants by the magic number `0x3FA8BDD1` and prints which trie engine was found:

```bash
# iOS 16 — shows actual keyword strings (from CFBurstTrie traversal)
./bin/emdreader -i FindReplace-en.dat

# iOS 17+ — shows payload table by key ID (keyword strings not extractable)
./bin/emdreader -i LocaleData-en.dat

# CharacterPicker.dat — same format, works identically
./bin/emdreader -i de.lproj/CharacterPicker.dat

# Find all entries mapping to emoji index 0x1
./bin/emdreader -i FindReplace-en.dat | grep '0x1[,\]]'
```

### iOS ≤16 output (keyword strings shown)
```
Format:             Emoji Keyword Search Index
Trie engine:        CFBurstTrie (iOS ≤16)
Keyword count:      7901

--- Keyword -> Emoji Index Table (7901 entries) ---
smile                          -> [0x1, 0x2, 0x3, 0x9]
smiley                         -> [0x1, 0x4]
```

### iOS 17+ output (key IDs shown)
```
Format:             Emoji Keyword Search Index
Trie engine:        Marisa LOUDS (iOS 17+)
Keyword count:      16459

--- Keyword Payload Table (16459 entries) ---
[    0] start=0x0508  count=1   -> [0x3B2]
[    1] start=0x0229  count=2   -> [0x2CF, 0x2D0]
```

> **Note (iOS 17+):** Keyword strings are stored inside the Marisa trie and cannot be enumerated without `libmarisa`. Entries are displayed by key ID (0-based insertion order). To map key IDs back to strings, use the Marisa C API separately.
