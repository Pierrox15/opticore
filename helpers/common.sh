# helpers/common.sh

# ============================================================================
# FONCTIONS de loggins:
# ============================================================================

# --- CODES COULEURS ---
C_RESET='\e[0m'
C_INFO='\e[1;34m'    # Bleu
C_SUCCESS='\e[1;32m' # Vert
C_WARN='\e[1;33m'    # Jaune
C_ERROR='\e[1;31m'   # Rouge

ob_info() {
    echo -e ">>> [${C_INFO}INFO${C_RESET}] $1"
}

ob_success() {
    echo -e ">>> [${C_SUCCESS}SUCCESS${C_RESET}] $1"
}

ob_warn() {
    echo -e ">>> [${C_WARN}WARN${C_RESET}] $1"
}

ob_error() {
    echo -e ">>> [${C_ERROR}ERREUR${C_RESET}] $1" >&2
    exit 1
}

# ==============================================================================
# FONCTION : ob_git_sync
# DESCRIPTION : Synchronise un dépôt Git local avec un dépôt distant.
#               Gère intelligemment les clones initiaux, les mises à jour (pull),
#               le basculement entre branches/tags, et la profondeur d'historique.
#
# ARGUMENTS :
#   $1 - REPO_URL   : URL du dépôt Git (ex: https://github.com/user/repo.git)
#   $2 - TARGET_DIR : Chemin absolu du dossier local de destination
#   $3 - BRANCH_TAG : (Optionnel) Nom de la branche ou du tag cible. Défaut : 'master'
#   $4 - DEPTH      : (Optionnel) Profondeur du clone (shallow). Défaut : 1
#                     Renseigner '0' pour récupérer l'historique complet.
#
# EXEMPLES D'UTILISATION :
#   ob_git_sync "https://..." "/opt/.../src/moteur"                 # master (depth 1)
#   ob_git_sync "https://..." "/opt/.../src/moteur" "v1.2.0"        # tag v1.2.0 (depth 1)
#   ob_git_sync "https://..." "/opt/.../src/moteur" "dev" "0"       # branche dev (historique complet)
#
# VARIABLES EXPORTÉES (Utilisables par le script parent après l'appel) :
#   $OB_GIT_SHORT_SHA, $OB_GIT_LOCAL_SHA, $OB_GIT_REMOTE_SHA
# ==============================================================================
ob_git_sync() {
    local repo_url="$1"
    local target_dir="$2"
    local branch_tag="${3:-master}" # master par défaut
    local clone_depth="${4:-1}"     # Depth 1 par défaut, mettre 0 pour un historique complet

    # Préparation de l'argument de profondeur
    local depth_args=()
    if [ "$clone_depth" -gt 0 ]; then
        depth_args=("--depth" "$clone_depth")
    fi

    ob_info "Synchronisation Git (Cible: $branch_tag | Depth: $clone_depth) -> $repo_url"

    if [ ! -d "$target_dir" ]; then
        ob_info "Nouveau dépôt détecté. Clonage en cours..."
        mkdir -p "$(dirname "$target_dir")"

        git clone "${depth_args[@]}" --branch "$branch_tag" "$repo_url" "$target_dir" || ob_error "Échec du git clone."
        cd "$target_dir" || ob_error "Dossier introuvable après clonage."
    else
        cd "$target_dir" || ob_error "Dossier source inaccessible."
        ob_info "Dépôt existant. Nettoyage des patchs et actualisation..."

        # 1. NETTOYAGE BRUTAL : On détruit toute modification locale (nos anciens 'sed')
        git reset --hard HEAD >/dev/null 2>&1
        git clean -fdx >/dev/null 2>&1

        # 2. FETCH : On récupère les nouveautés du distant
        git remote set-branches origin "$branch_tag"
        git fetch "${depth_args[@]}" origin "$branch_tag" || ob_error "Échec du fetch de la cible '$branch_tag'."

        # 3. CHECKOUT : On s'assure d'être sur la bonne cible
        git checkout "$branch_tag" >/dev/null 2>&1 || ob_error "La branche ou le tag '$branch_tag' n'existe pas."

        # 4. ALIGNEMENT STRICT (Remplace le git pull)
        if git symbolic-ref -q HEAD >/dev/null 2>&1; then
            # Si c'est une branche, on s'aligne de force sur le distant
            git reset --hard "origin/$branch_tag" >/dev/null 2>&1 || ob_error "Échec de l'alignement forcé sur le distant."
        else
            ob_warn "Dépôt figé sur un Tag/Commit (Detached HEAD). Reset distant ignoré."
        fi
    fi

    # Exportation des variables pour le script de build
    export OB_GIT_SHORT_SHA=$(git rev-parse --short HEAD)
    export OB_GIT_LOCAL_SHA=$(git rev-parse HEAD)
    export OB_GIT_REMOTE_SHA=$(git rev-parse @{u} 2>/dev/null || echo "detached")
}

# ==============================================================================
# FONCTION : ob_build_check
# DESCRIPTION : Détermine si une compilation est nécessaire ou si elle doit être
#               ignorée. Gère le signal d'environnement OB_FORCE_BUILD.
#               Si la compilation est inutile, coupe immédiatement le script appelant.
#
# ARGUMENTS :
#   $1 - ENGINE_NAME : Le nom du moteur pour l'affichage (ex: ironwail)
#   $2 - BINARY_PATH : Le chemin absolu du binaire final attendu
# ==============================================================================
ob_build_check() {
    local engine_name="$1"
    local binary_path="$2"

    # 1. Bypass du SKIP : Si Force = 0, on vérifie si on peut ignorer la compilation
    if [ "${OB_FORCE_BUILD:-0}" -eq 0 ] && [ "$OB_GIT_LOCAL_SHA" == "$OB_GIT_REMOTE_SHA" ] && [ -f "$binary_path" ]; then
        ob_info "[SKIP] ${engine_name} est déjà à jour (Commit: ${OB_GIT_SHORT_SHA})."
        # ATTENTION : Comme la fonction est sourcée, cet exit va couper le script de build parent !
        exit 0
    fi

    # 2. Message adapté selon la situation
    if [ "${OB_FORCE_BUILD:-0}" -eq 1 ]; then
        ob_warn "Mode FORCE activé : Ignorer la vérification Git et forcer une recompilation propre."
    else
        ob_info "[UPDATE] Nouveau commit ou binaire manquant. Compilation en cours..."
    fi
}

# ------------------------------------------------------------------------------
# FONCTION    : ob_check_pkg
# DESCRIPTION : Vérifie la présence d'une liste de binaires/commandes sur le système.
#               Stoppe l'exécution du script parent si une dépendance manque, et
#               génère la commande 'apt install' correspondante.
# Arguments   : Liste des dépendances séparées par des espaces.
# ------------------------------------------------------------------------------
ob_check_pkg() {
    local missing_pkgs=()

    ob_info "Vérification des paquets Debian requis..."

    for pkg in "$@"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            echo -e "    [${C_ERROR}MANQUANT${C_RESET}] $pkg"
            missing_pkgs+=("$pkg")
        else
            echo -e "    [${C_SUCCESS}OK${C_RESET}] $pkg"
        fi
    done

    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        ob_warn "Des dépendances sont manquantes : ${missing_pkgs[*]}"

        # On demande confirmation à l'utilisateur
        read -p ">>> Voulez-vous les installer maintenant ? (o/n) " -n 1 -r
        echo # Nouvelle ligne après la saisie

       if [[ $REPLY =~ ^[Oo]$ ]]; then
           ob_info "Lancement de l'installation (mot de passe ROOT requis)..."

           # Utilisation de 'su - root -c'
           # On encapsule les commandes apt dans une chaîne passée à l'environnement root.
           if su - root -c "apt update && apt install -y ${missing_pkgs[*]}"; then
               ob_success "Dépendances installées ! Reprise du script..."
           else
               ob_error "L'installation a échoué (mot de passe incorrect, réseau ou apt lock)."
           fi
       else
           ob_error "Installation annulée par l'utilisateur."
       fi
    fi
}