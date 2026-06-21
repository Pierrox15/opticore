#!/bin/bash
# ==============================================================================
# Script : deploy-lab.sh
# Rôle : Synchronisation parallèle agressive de l'environnement vers les nœuds
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${SCRIPT_DIR}/../globals.conf"
source "${OB_CORE_HELPERS}/common.sh"

# Liste de tes machines cibles (IPs ou noms d'hôtes générés par ton preseed)
# Exemple : NODES=("optibox-1a2b" "optibox-3c4d" "optibox-5e6f")
NODES=(
    "192.168.1.90"
)

# Les dossiers précis que tu souhaites synchroniser
DIRS_TO_SYNC=(
    "/opt/games/dist"
    "/opt/games/engines"
    "/opt/games/assets"
    "/opt/games/launch"
    "/opt/games/libs"
    "/opt/wine"
    "/opt/wineprefixes"
)

# Options ultra-optimisées pour un LAN de confiance :
# -a : Archive (conserve les droits, symlinks, dates)
# -H : Conserve les hardlinks
# --numeric-ids : Évite de perdre du temps à résoudre les noms d'utilisateurs (parfait car ton preseed a mis le même UID "pierre" partout)
# --delete : EFFACE sur la cible ce qui n'existe plus sur le maître (Miroir parfait)
RSYNC_OPTS="-aH --numeric-ids --delete"

# On force un SSH ultra-léger sans compression
SSH_OPTS="-o Cipher=aes128-gcm@openssh.com -o Compression=no -o StrictHostKeyChecking=no"

ob_info "Début du déploiement massif vers ${#NODES[@]} machines..."

# Boucle de lancement parallèle
for node in "${NODES[@]}"; do
    ob_info "Lancement du flux réseau vers $node..."

    # Le '&' à la fin est vital : il lance le rsync en arrière-plan (background job)
    rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" "${DIRS_TO_SYNC[@]}" "root@$node:/opt/games/"
done

# Le script attend que toutes les tâches en arrière-plan soient terminées
wait

ob_success "Synchronisation de l'essaim terminée avec succès !"