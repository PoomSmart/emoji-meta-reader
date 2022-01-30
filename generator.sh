#!/bin/sh

if [ -z $1 ];then
  echo "emojimeta.dat path required"
  exit 1
fi

./bin/emdreader -i $1 -e 1 -o ./emojimeta_legacy.dat
./bin/emdreader -i $1 -e 0 -o ./emojimeta_legacy_10.dat
cp -fv ./emojimeta_legacy.dat ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_legacy.dat
cp -fv ./emojimeta_legacy_10.dat ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_legacy_10.dat
cp -fv $1 ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_modern.dat
rm -f emojimeta_legacy*.dat
