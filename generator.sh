#!/usr/bin/env bash

if [ -z $1 ];then
  echo "emojimeta.dat path required"
  exit 1
fi

./bin/emdreader -i $1 -e 2 -o ./emojimeta_2.dat
./bin/emdreader -i $1 -e 1 -o ./emojimeta_1.dat
./bin/emdreader -i $1 -e 0 -o ./emojimeta_0.dat
cp -fv ./emojimeta_2.dat ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_2.dat
cp -fv ./emojimeta_1.dat ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_1.dat
cp -fv ./emojimeta_0.dat ../EmojiPort-10-Resources/layout/System/Library/PrivateFrameworks/CoreEmoji.framework/emojimeta_0.dat
rm -f emojimeta_*.dat
