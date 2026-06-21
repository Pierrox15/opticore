#!/bin/bash
# core/scripts/miscs/netradiant-custom.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${SCRIPT_DIR}/../../globals.conf"
source "${OB_CORE_HELPERS}/common.sh"

ob_check_pkg build-essential pkg-config git unzip wget libxml2-dev libjpeg-dev libpng-dev libgl1-mesa-dev qtbase5-dev libqt5svg5-dev libassimp-dev

BUILD_DIR="${OB_CORE_SRC}"
TARGET_DIR="/opt/games/tools/netradiant-custom"

mkdir -p "$OB_CORE_LOG"
LOG_FILE="$OB_CORE_LOG/netradiant_custom_$(date +%F).log"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

ob_info "[2/4] Récupération des sources de NetRadiant-custom (Garux)..."
if [ -d "netradiant-custom" ]; then
    echo -e "Le dossier existe déjà, mise à jour des sources..."
    cd netradiant-custom
    git reset --hard
    git pull
else
    git clone --recursive https://github.com/Garux/netradiant-custom.git
    cd netradiant-custom
fi

ob_info "[3/4] Compilation directe via Makefile (Multi-threading)..."
# Pas de dossier build séparé, Garux compile tout à la racine du dépôt
make clean

# Lancement du build natif de Garux (le flag release est géré par son arborescence)
# On redirige les logs proprement
make BUILD=release -j"$OB_MAKE_JOBS" 2>&1 | tee -a "$LOG_FILE"

ob_info "[4/4] Installation dans ${TARGET_DIR}..."
# Le Makefile de Garux compile tout dans un sous-dossier nommé 'install' à la racine
if [ -d "install" ]; then
    sudo mkdir -p "$TARGET_DIR"
    sudo cp -r install/* "$TARGET_DIR/"
    sudo chown -R "$USER":"$USER" "$TARGET_DIR"
else
    ob_error "Erreur : Le dossier 'install' n'a pas été généré par le Makefile."
    exit 1
fi

ob_success "==============================================================="
ob_success "[OK] NetRadiant-custom (Garux-Qt5) a été forgé avec succès !"
ob_success "L'éditeur est disponible ici : ${TARGET_DIR}/radiant.x86_64"
ob_success "==============================================================="