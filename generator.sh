#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMDREADER="${SCRIPT_DIR}/bin/emdreader"
EMOJIPORT="${SCRIPT_DIR}/../EmojiPort-10-Resources"
OUTDIR_MAIN="${EMOJIPORT}/layout/System/Library/PrivateFrameworks/CoreEmoji.framework"
OUTDIR_17="${EMOJIPORT}/assets-17/layout/System/Library/PrivateFrameworks/CoreEmoji.framework"
OUTDIR_16="${EMOJIPORT}/assets-16/layout/System/Library/PrivateFrameworks/CoreEmoji.framework"

cleanup() {
    rm -f "${SCRIPT_DIR}"/emojimeta_*.dat
}
trap cleanup EXIT

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <path-to-CoreEmoji.framework>" >&2
    exit 1
fi

FRAMEWORK="$1"
if [[ ! -d "$FRAMEWORK" ]]; then
    echo "Error: Framework directory '$FRAMEWORK' not found" >&2
    exit 1
fi

if [[ ! -x "$EMDREADER" ]]; then
    echo "Error: emdreader not found or not executable at '$EMDREADER'" >&2
    echo "Run 'make' first to build the tool" >&2
    exit 1
fi

EMOJIMETA="${FRAMEWORK}/emojimeta.dat"
if [[ ! -f "$EMOJIMETA" ]]; then
    echo "Error: emojimeta.dat not found at '$EMOJIMETA'" >&2
    exit 1
fi

# ────────────────────────────────────────────────────────────────
# 1. Convert emojimeta.dat to all format variants
# ────────────────────────────────────────────────────────────────
echo "Converting emojimeta.dat to all format variants..."
"$EMDREADER" -i "$EMOJIMETA" -e 2 -o "${SCRIPT_DIR}/emojimeta_2.dat"
"$EMDREADER" -i "$EMOJIMETA" -e 1 -o "${SCRIPT_DIR}/emojimeta_1.dat"
"$EMDREADER" -i "$EMOJIMETA" -e 0 -o "${SCRIPT_DIR}/emojimeta_0.dat"

echo "Copying emojimeta files to EmojiPort resources..."
cp -fv "$EMOJIMETA"                       "${OUTDIR_MAIN}/emojimeta_3.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_2.dat"   "${OUTDIR_MAIN}/emojimeta_2.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_1.dat"   "${OUTDIR_MAIN}/emojimeta_1.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_0.dat"   "${OUTDIR_MAIN}/emojimeta_0.dat"

# ────────────────────────────────────────────────────────────────
# 2. Convert keyword search index files
#    For each SOURCE.dat: copy as SOURCE2.dat and convert to SOURCE_16.dat
# ────────────────────────────────────────────────────────────────

# convert_trie <src> <rel_dir> <basename_without_ext>
# Copies src as <basename>2.dat in OUTDIR_17/<rel_dir> and converts to
# <basename>_16.dat in OUTDIR_16/<rel_dir>.
convert_trie() {
    local src="$1"
    local rel_dir="$2"
    local base="$3"
    local dst17="${OUTDIR_17}${rel_dir:+/$rel_dir}"
    local dst16="${OUTDIR_16}${rel_dir:+/$rel_dir}"

    mkdir -p "$dst17" "$dst16"
    echo "  [copy]    ${dst17}/${base}2.dat"
    cp -f "$src" "${dst17}/${base}2.dat"
    echo "  [convert] ${dst16}/${base}_16.dat"
    "$EMDREADER" -i "$src" -e 16 -o "${dst16}/${base}_16.dat"
}

echo "Converting keyword search index files..."

# Top-level Emoticons.dat (language-neutral, present in all iOS versions)
if [[ -f "${FRAMEWORK}/Emoticons.dat" ]]; then
    convert_trie "${FRAMEWORK}/Emoticons.dat" "" "Emoticons"
fi

# Top-level LocaleData-en.dat (present in iOS 17+)
if [[ -f "${FRAMEWORK}/LocaleData-en.dat" ]]; then
    convert_trie "${FRAMEWORK}/LocaleData-en.dat" "" "LocaleData-en"
fi

# Top-level FindReplace-en.dat (present in iOS ≤16 sources)
if [[ -f "${FRAMEWORK}/FindReplace-en.dat" ]]; then
    convert_trie "${FRAMEWORK}/FindReplace-en.dat" "" "FindReplace-en"
fi

# StaticAssets/ja and StaticAssets/zh.shared
for sa_dir in ja zh.shared; do
    src="${FRAMEWORK}/StaticAssets/${sa_dir}/LocaleData.dat"
    if [[ -f "$src" ]]; then
        convert_trie "$src" "StaticAssets/${sa_dir}" "LocaleData"
    fi
done

# Per-locale *.lproj files
for lproj_dir in "${FRAMEWORK}"/*.lproj; do
    [[ -d "$lproj_dir" ]] || continue
    locale="$(basename "$lproj_dir")"

    for trie_name in LocaleData CharacterPicker FindReplace; do
        src="${lproj_dir}/${trie_name}.dat"
        if [[ -f "$src" ]]; then
            convert_trie "$src" "${locale}" "$trie_name"
        fi
    done
done

echo "Done!"
