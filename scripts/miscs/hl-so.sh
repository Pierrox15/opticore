#!/bin/bash
# Compiler et déployer les lib.so pour Halflife et ses mods

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

source "${SCRIPT_DIR}/../../globals.conf"
source "${OB_CORE_HELPERS}/common.sh"

export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${CFLAGS}"

# Préparation et Récuperation des sources
cd ${OB_CORE_SRC}

if [ ! -d "hlsdk-portable" ]; then
    ob_info "=== CLONAGE INITIAL DU DÉPÔT ==="
    git clone https://github.com/FWGS/hlsdk-portable.git
else
    ob_info  "=== DÉPÔT TROUVÉ : MISE À JOUR ==="
fi

cd  ${OB_CORE_SRC}/hlsdk-portable

git fetch --all --prune &> /dev/null


# Tableau mod:branch:lib (le nom de la lib en sortie n'est pas tjrs identique au mod...)
GAMES_MATRIX="gearbox:opfor:opfor bshift:bshift:bshift tfc:tfc:tfc valve:master:hl "

ob_info "=== DÉBUT DE LA COMPILATION MULTI-BRANCHES ==="

for GAME in $GAMES_MATRIX; do
    # Extraction propre des variables via IFS (Internal Field Separator)
    IFS=':' read -r MOD BRANCH TARGET_DLL <<< "$GAME"
    TARGET_DIR="${OB_ASSETS_DIR}/half-life/${MOD}"

    if [ -d "$TARGET_DIR" ]; then
        echo ""
        ob_info ">>> Traitement : ${MOD} (Branche: ${BRANCH} -> Cible: ${TARGET_DLL}_amd64.so) <<<"

        git reset --hard HEAD &> /dev/null
        git clean -fdx &> /dev/null

        # On force l'alignement sur le code serveur
        git checkout -B "$BRANCH" "origin/$BRANCH" &> /dev/null
        git clean -fdx &> /dev/null

        ./waf distclean &> /dev/null
        ./waf configure -T release -8
        ./waf build -j"${OB_MAKE_JOBS:-$(nproc)}"

        ob_info "Déploiement et renommage"
        mkdir -p "${TARGET_DIR}/cl_dlls"
        mkdir -p "${TARGET_DIR}/dlls"

        # Le client s'appelle toujours client_amd64.so (pour l'affichage)
        if [ -f "build/cl_dll/client_amd64.so" ]; then
            cp "build/cl_dll/client_amd64.so" "${TARGET_DIR}/cl_dlls/"
        fi

        # Le serveur a un nom générique on le FORCE à prendre le nom definie dans le tableau de correspondance
        if [ -f "build/dlls/hl_amd64.so" ]; then
            cp "build/dlls/hl_amd64.so" "${TARGET_DIR}/dlls/${TARGET_DLL}_amd64.so"
        elif [ -f "build/${MOD}/dlls/hl_amd64.so" ]; then
            # Sécurité si Waf a créé un sous-dossier
            cp "build/${MOD}/dlls/hl_amd64.so" "${TARGET_DIR}/dlls/${TARGET_DLL}_amd64.so"
        elif [ -f "build/dlls/opfor_amd64.so" ]; then
            cp "build/dlls/opfor_amd64.so" "${TARGET_DIR}/dlls/opfor_amd64.so"
        fi

        echo "[SUCCÈS] Bibliothèques de ${MOD} injectées et renommées en ${TARGET_DLL}."
        git checkout master &> /dev/null
    fi
done

ob_success "=== COMPILATIONS TERMINÉES ==="