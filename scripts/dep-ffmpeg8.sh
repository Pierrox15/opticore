#!/bin/bash
# builds/scripts/dep-ffmpeg8.sh

# 1. Chargement de la config globale
source "$(dirname "$0")/../global.conf"

FFMPEG_VER="8.0"
FFMPEG_SRC="$SOURCES_DIR/ffmpeg-$FFMPEG_VER"
FFMPEG_PREFIX="$LIBS_DIR/ffmpeg8"

echo ">>> Préparation de FFmpeg $FFMPEG_VER (Optimisé Yorkfield)"

# 2. Récupération des sources
if [ ! -d "$FFMPEG_SRC" ]; then
    mkdir -p "$SOURCES_DIR"
    wget -qO- https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.bz2 | tar xvj -C "$SOURCES_DIR"
fi

cd "$FFMPEG_SRC" || exit 1

# 3. Configuration spécifique pour moteur de jeu
# On active uniquement ce qui est nécessaire pour RealRTCW pour plus de légèreté
echo ">>> Configuration avec préfixe : $FFMPEG_PREFIX"
./configure \
    --prefix="$FFMPEG_PREFIX" \
    --extra-cflags="$CFLAGS" \
    --extra-ldflags="-flto=auto" \
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-programs \
    --enable-pic \
    --enable-gpl \
    --enable-swscale \
    --enable-avcodec \
    --enable-avformat

# 4. Compilation Yorkfield (Jobs: nproc+1)
echo ">>> Compilation (Jobs: $MAKE_JOBS)..."
make -j"$MAKE_JOBS"
make install

echo ">>> FFmpeg 8 installé dans $FFMPEG_PREFIX"