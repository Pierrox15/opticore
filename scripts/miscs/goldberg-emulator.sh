#!/bin/bash
# core/scripts/miscs/goldberg-emulator.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${SCRIPT_DIR}/../../globals.conf"
source "${OB_CORE_HELPERS}/common.sh"

WORKDIR="${OB_LIBS_DIR}/goldberg"
TARGET_DIR="${WORKDIR}/goldberg_emulator"
LOG_FILE="${OB_CORE_LOG}/goldberg_emulator_$(date +%F).log"
GIT_SRC="https://gitlab.com/Mr_Goldberg/goldberg_emulator.git"

# Si une commande plante avant un pipe (|), tout s'arrête en erreur
set -o pipefail

# === DEBUT du SCRIPT ===

ob_check_pkg build-essential git g++-multilib gcc-multilib clang protobuf-compiler libprotobuf-dev libprotobuf-dev:i386

ob_info "Récupération des sources"
ob_git_sync $GIT_SRC "$TARGET_DIR" "master" "1"

cd "$TARGET_DIR" || ob_error "Impossible d'accéder au dossier source après la synchronisation."

ob_info "Application des patchs pour Glibc (Debian 13)..."
# On remplace les appels obsolètes par les standards POSIX modernes
sed -i 's/__xstat64(ver, /stat64(/g' dll/wrap.cpp
sed -i 's/__lxstat64(ver, /lstat64(/g' dll/wrap.cpp
sed -i 's/__fxstat64(ver, /fstat64(/g' dll/wrap.cpp
sed -i 's/__xstat(ver, /stat(/g' dll/wrap.cpp
sed -i 's/__lxstat(ver, /lstat(/g' dll/wrap.cpp
sed -i 's/__fxstat(ver, /fstat(/g' dll/wrap.cpp
sed -i 's/__xmknod(1, path_lowercased, mode, &dev)/mknod(path_lowercased, mode, dev)/g' dll/wrap.cpp

ob_info "Phase 1/2 : Compilation 64-bit (amd64)..."

make clean 2>&1 | tee -a "$LOG_FILE"
make -j"${OB_MAKE_JOBS:-1}" CXX="g++" CXXFLAGS="${CXXFLAGS} -fPIC" LDFLAGS="${LDFLAGS}" 2>&1 | tee -a "$LOG_FILE" || ob_error "Échec critique de la compilation 64-bit. Consultez $LOG_FILE."

if [ -f "libsteam_api.so" ]; then
    cp libsteam_api.so ../libsteam_api_amd64.so
    ob_success "libsteam_api_amd64.so généré avec succès."
else
    ob_error "Binaire 64-bit introuvable après compilation."
fi

ob_info "Phase 2/2 : Compilation 32-bit (i386)..."

make clean 2>&1 | tee -a "$LOG_FILE"
make -j"${OB_MAKE_JOBS:-1}" CXX="g++ -m32" CXXFLAGS="${CXXFLAGS} -fPIC -m32" LDFLAGS="${LDFLAGS} -m32" 2>&1 | tee -a "$LOG_FILE" || ob_error "Échec critique de la compilation 32-bit. Consultez $LOG_FILE."

if [ -f "libsteam_api.so" ]; then
    cp libsteam_api.so ../libsteam_api_i386.so
    ob_success "libsteam_api_i386.so généré avec succès."
else
    ob_error "Binaire 32-bit introuvable après compilation."
fi

ob_info "Opération terminée. Les bibliothèques natives sont prêtes dans : $WORKDIR"
ls -lh ../*.so