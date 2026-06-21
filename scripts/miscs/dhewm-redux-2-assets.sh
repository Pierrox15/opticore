#!/bin/bash

INPUT_DIR="/opt/games/core/src/dhewm3-redux-assets"
OUTPUT_DIR="/opt/games/assets/doom3/redux"

echo "--- Début de l'extraction des assets visuels de Redux ---"

# Vérification de l'existence du dossier source
if [ ! -d "$INPUT_DIR" ]; then
    echo "[ERREUR] Le dossier source '$INPUT_DIR' est introuvable."
    exit 1
fi

# 1. Création du dossier de sortie et conversion en chemin absolu (pour le zip)
mkdir -p "$OUTPUT_DIR"
OUTPUT_ABS_DIR=$(cd "$OUTPUT_DIR" && pwd)

# 2. Compression des textures "en vrac" en un seul fichier .pk4
# On se déplace dans INPUT_DIR pour que l'archive zip contienne 'textures/...' et non '/opt/games/...'
if [ -d "$INPUT_DIR/textures" ]; then
    echo "[...] Compression des 2000+ textures HD en vrac..."
    (cd "$INPUT_DIR" && zip -r -q "$OUTPUT_ABS_DIR/z_redux_00_loose_textures.pk4" textures/)
    echo "[OK] Textures compressées dans z_redux_00_loose_textures.pk4"
else
    echo "[ERREUR] Le dossier 'textures/' est introuvable dans '$INPUT_DIR'."
fi

# 3. Récupération et renommage des archives d'assets purs (.pk4)
echo "[...] Copie et pacification des archives .pk4..."

# Liste des fichiers sûrs pour les assets visuels/sonores (on exclut game00 et les UI)
SAFE_PAKS=(
    "pak_cleanfiles.pk4"
    "pak_flashlight.pk4"
    "pak_modfiles.pk4"
    "pak_xpfiles.pk4"
    "zpak006.pk4"
)

# Boucle de copie avec préfixe de priorité
for pak in "${SAFE_PAKS[@]}"; do
    if [ -f "$INPUT_DIR/$pak" ]; then
        cp "$INPUT_DIR/$pak" "$OUTPUT_ABS_DIR/z_redux_01_${pak}"
        echo "  -> Transformé : $pak"
    else
        echo "  -> [ATTENTION] Fichier introuvable : $pak"
    fi
done

# 4. Traitement optionnel des cartes (Maps)
if [ -f "$INPUT_DIR/pak_modfilesmaps.pk4" ]; then
    cp "$INPUT_DIR/pak_modfilesmaps.pk4" "$OUTPUT_ABS_DIR/z_redux_02_MAPS_pak_modfilesmaps.pk4"
    echo "  -> [INFO] Cartes Redux isolées dans z_redux_02_MAPS_pak_modfilesmaps.pk4"
    echo "     (À supprimer de votre variante Coop si le serveur utilise les cartes originales)"
fi

echo "--- Terminé ! Vos assets sont prêts dans le dossier : $OUTPUT_ABS_DIR ---"