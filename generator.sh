#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMDREADER="${SCRIPT_DIR}/bin/emdreader"
OUTPUT_DIR="../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework"

cleanup() {
    rm -f "${SCRIPT_DIR}"/emojimeta_*.dat
}
trap cleanup EXIT

if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <path-to-emojimeta.dat>" >&2
    exit 1
fi

if [[ ! -f "$1" ]]; then
    echo "Error: Input file '$1' not found" >&2
    exit 1
fi

if [[ ! -x "$EMDREADER" ]]; then
    echo "Error: emdreader not found or not executable at '$EMDREADER'" >&2
    echo "Run 'make' first to build the tool" >&2
    exit 1
fi

echo "Converting emojimeta.dat to all format variants..."
"$EMDREADER" -i "$1" -e 2 -o "${SCRIPT_DIR}/emojimeta_2.dat"
"$EMDREADER" -i "$1" -e 1 -o "${SCRIPT_DIR}/emojimeta_1.dat"
"$EMDREADER" -i "$1" -e 0 -o "${SCRIPT_DIR}/emojimeta_0.dat"

echo "Copying files to EmojiPort resources..."
cp -fv "$1" "${OUTPUT_DIR}/emojimeta_3.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_2.dat" "${OUTPUT_DIR}/emojimeta_2.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_1.dat" "${OUTPUT_DIR}/emojimeta_1.dat"
cp -fv "${SCRIPT_DIR}/emojimeta_0.dat" "${OUTPUT_DIR}/emojimeta_0.dat"

echo "Done!"
