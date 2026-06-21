#!/bin/bash
# builds/scripts/iortcw.sh

# CONFIGURATION
source "$(dirname "$0")/../global.conf"

ENGINE=iortcw
ENGINE_LABEL="iortcw"
ENGINE_PORT="Return to Castle Wolfenstein (SP & MP)"
ENGINE_FEATURES="Moteur id Tech 3, support 64-bit, rendus OpenGL modernes, correction de bugs vanilla"

REPO_URL="https://github.com/iortcw/iortcw.git"
REPO_BRANCH="master"
REPO_DEPTH=1

LOCAL_SOURCE="$SOURCES_DIR/${ENGINE}"
LOG_FILE="$LOGS_DIR/${ENGINE}_$(date +%F).log"
ENGINE_DEST_DIR="${ENGINES_DIR}/${ENGINE}"

echo ">>> Préparation des sources pour ${ENGINE_LABEL}..."

# Gestion du dépôt
if [ ! -d "$LOCAL_SOURCE" ]; then
    mkdir -p "$SOURCES_DIR"
    git clone --depth ${REPO_DEPTH:-1} --branch "$REPO_BRANCH" "$REPO_URL" "$LOCAL_SOURCE"
else
    cd "$LOCAL_SOURCE" && git pull
fi

GIT_SHA=$(git -C "$LOCAL_SOURCE" rev-parse --short HEAD)

# Vérification de mise à jour
ARCH=$(uname -m)
if [ -f "${ENGINE_DEST_DIR}/iowolfsp.${ARCH}" ] && [ -f "${ENGINE_DEST_DIR}/iowolfmp.${ARCH}" ]; then
    LOCAL_SHA=$(git -C "$LOCAL_SOURCE" rev-parse HEAD)
    REMOTE_SHA=$(git -C "$LOCAL_SOURCE" rev-parse @{u} 2>/dev/null || echo "unknown")

    if [ "$LOCAL_SHA" == "$REMOTE_SHA" ]; then
        echo ">>> [SKIP] ${ENGINE} est déjà à jour."
        exit 0
    fi
fi

echo ">>> [UPDATE] Compilation des versions SP et MP..."

# --- COMPILATION MULTIPLAYER ---
echo ">>> Compilation MP..."
cd "$LOCAL_SOURCE/MP" || exit 1
make clean
# On force le build dans un dossier local pour mieux le capturer
make -j"$MAKE_JOBS" BUILD_DIR=build 2>&1 | tee "$LOG_FILE"

# --- COMPILATION SINGLEPLAYER ---
echo ">>> Compilation SP..."
cd "$LOCAL_SOURCE/SP" || exit 1
make clean
make -j"$MAKE_JOBS" BUILD_DIR=build 2>&1 | tee -a "$LOG_FILE"

# --- INSTALLATION CIBLÉE ---
mkdir -p "${ENGINE_DEST_DIR}"

echo ">>> Extraction des binaires depuis les dossiers de build..."

# iortcw crée un dossier type "release-linux-x86_64" à l'intérieur de BUILD_DIR
# On utilise find pour copier tout le contenu du dossier release (binaires + .so)
cp -r "$LOCAL_SOURCE/MP/build/"release-linux-${ARCH}/* "${ENGINE_DEST_DIR}/"
cp -r "$LOCAL_SOURCE/SP/build/"release-linux-${ARCH}/* "${ENGINE_DEST_DIR}/"

# Nettoyage des fichiers objets inutiles dans la destination (on ne garde que les binaires et .so)
find "${ENGINE_DEST_DIR}" -name "*.o" -type f -delete

# Vérification et génération du .info
if [ -f "${ENGINE_DEST_DIR}/iowolfsp.${ARCH}" ]; then
    echo ">>> Génération de ${ENGINE}.info..."
    ENGINE_DESC="
## Engine: ${ENGINE_LABEL} (${ENGINE_PORT})
* **Git Version** : ${GIT_SHA}
* **Build date** : $(date +%F)
* **Build flags** : ${CFLAGS}
"
    echo -e "$ENGINE_DESC" > "${ENGINE_DEST_DIR}/${ENGINE}.info"
    echo ">>> Build iortcw terminé."
else
    echo "ERREUR : Les binaires n'ont pas été trouvés dans ${ENGINE_DEST_DIR}"
    exit 1
fi