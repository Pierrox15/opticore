#!/bin/bash
# Compiler et déployer le client natif 64-bit pour Counter-Strike et Condition Zero
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

source "${SCRIPT_DIR}/../../globals.conf"
source "${OB_CORE_HELPERS}/common.sh"

export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${CFLAGS}"

#  Préparation et Récuperation des sources
cd ${OB_CORE_SRC}
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${CFLAGS}"

if [ ! -d "cs16-client" ]; then
    echo "=== CLONAGE DU DÉPÔT (VELARON / CMAKE) ==="
    git clone --recursive https://github.com/Velaron/cs16-client.git
else
    echo "=== DÉPÔT TROUVÉ : MISE À JOUR ==="
fi

cd cs16-client

ob_info "Nettoyage de l'environnement..."
git fetch --all --prune &> /dev/null
git reset --hard HEAD &> /dev/null
git clean -fdx &> /dev/null
git checkout master &> /dev/null

# CONFIGURATION CMAKE ET COMPILATION ---
ob_info "Configuration de l'environnement CMake..."

# Création du dossier de build
mkdir -p build
cd build

# L'option Release désactive le mode debug
cmake .. -DCMAKE_BUILD_TYPE=Release

ob_info "   -> Compilation en cours..."

make -j"${OB_MAKE_JOBS:-$(nproc)}"

TARGET_DIR="${OB_ASSETS_DIR}/half-life/czero"

if [ -d "$TARGET_DIR" ]; then
    echo ""
    ob_info "   -> Déploiement des bibliothèques dynamiques..."

    mkdir -p "${TARGET_DIR}/cl_dlls"
    mkdir -p "${TARGET_DIR}/dlls"

    # Le Client
    CLIENT_LIB=$(find . -name "client*.so" -type f | head -n 1)
    if [ -n "$CLIENT_LIB" ]; then
        cp "$CLIENT_LIB" "${TARGET_DIR}/cl_dlls/client_amd64.so"
        ob_info "[INJECTION] Client copié (client_amd64.so)."
    fi

    # Le Serveur
    SERVER_LIB=$(find 3rdparty/ReGameDLL_CS -name "cs*.so" -type f | head -n 1)
    if [ -n "$SERVER_LIB" ]; then
        # Pour CZ, le serveur s'appelle toujours mp.so ou mp_amd64.so
        cp "$SERVER_LIB" "${TARGET_DIR}/dlls/mp_amd64.so"
        ob_info "[INJECTION] Serveur ReGameDLL copié (mp_amd64.so)."
    fi

    # Les Bots
    BOT_LIB=$(find 3rdparty/yapb -name "yapb*.so" -type f | head -n 1)
    if [ -n "$BOT_LIB" ]; then
        cp "$BOT_LIB" "${TARGET_DIR}/dlls/yapb_amd64.so"
        ob_info "[INJECTION] Intelligence Artificielle (YaPB) copiée."
    fi

    MENU_LIB=$(find 3rdparty/mainui_cpp -name "*.so" -type f | head -n 1)
    if [ -n "$MENU_LIB" ]; then
        cp "$MENU_LIB" "${TARGET_DIR}/cl_dlls/menu_amd64.so"
        ob_info "[INJECTION] Interface des menus copiée (menu_amd64.so)."
    fi

    ob_success "Condition Zero prêt."
else
    ob_error "Le dossier ${TARGET_DIR} introuvable"
fi

ob_info "=== OPÉRATION TERMINÉE ==="