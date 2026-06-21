#!/bin/bash
# core/opticore.sh
# CLI Central pour l'administration du projet OptiBox

# 1. Chargement de la configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
source "${SCRIPT_DIR}/globals.conf"

if [ -f "${OB_CORE_HELPERS}/common.sh" ]; then
    source "${OB_CORE_HELPERS}/common.sh"
fi

# --- PRE-FLIGHT CHECKS (SÉCURITÉ & DROITS) ---

# 1. Blocage strict de l'exécution en Root
if [ "$EUID" -eq 0 ]; then
    echo -e ">>> [\e[1;31mERREUR FATALE\e[0m] Ce script ne doit ABSOLUMENT PAS être exécuté en root !"
    echo -e ">>> La compilation générerait des fichiers verrouillés. Utilisez votre compte standard ($OB_USER)."
    exit 1
fi

# 2. Validation des permissions système
check_permissions() {
    # Test 1 : La racine globale (/opt/games) existe-t-elle et est-elle inscriptible ?
    if [ ! -d "$OB_DIR" ] || [ ! -w "$OB_DIR" ]; then
        echo -e ">>> [\e[1;31mERREUR DE PERMISSIONS\e[0m] Accès refusé à l'environnement : $OB_DIR"
        echo -e ">>> Le dossier de base n'existe pas ou ne vous appartient pas."
        echo -e ""
        echo -e ">>> Copiez-collez ces commandes pour préparer le système :"
        echo -e "    \e[1;33msudo mkdir -p $OB_DIR\e[0m"
        echo -e "    \e[1;33msudo chown -R $USER:$USER $OB_DIR\e[0m"
        exit 1
    fi

    # Test 2 : Y a-t-il des sous-dossiers verrouillés par erreur ?
    local locked_dirs=()
    local dirs=("$OB_DIST_DIR" "$OB_ASSETS_DIR" "$OB_LAUNCH_DIR" "$OB_LIBS_DIR" "$OB_ENGINES_DIR" "$OB_CORE_SRC" "$OB_CORE_LOG" "$OB_CORE_HELPERS" "$OB_CORE_SCRIPTS")

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ] && [ ! -w "$dir" ]; then
            locked_dirs+=("$dir")
        fi
    done

    if [ ${#locked_dirs[@]} -gt 0 ]; then
        echo -e ">>> [\e[1;31mERREUR DE PERMISSIONS\e[0m] Certains dossiers existants sont verrouillés en écriture :"
        for d in "${locked_dirs[@]}"; do
            echo -e "    - $d"
        done
        echo -e ""
        echo -e ">>> Copiez-collez cette commande pour réattribuer les droits à votre utilisateur :"
        echo -e "    \e[1;33msudo chown -R $USER:$USER $OB_DIR\e[0m"
        exit 1
    fi
}

# On exécute le check avant toute autre action
check_permissions

# --- FONCTIONS INTERNES ---

show_help() {
    echo -e "\e[1;36mOptiCore CLI - Gestionnaire OptiBox\e[0m"
    echo -e "Utilisateur: \e[1;33m$OB_USER\e[0m | Hôte: \e[1;33m$OB_HOST\e[0m\n"
    echo -e "Usage: ./opticore.sh [OPTION] [ARGUMENT]"
    echo -e ""
    echo -e "Options globales:"
    echo -e "  -i, --init               Initialiser arborescence opticore (globals.conf)"
    echo -e "  -h, --help               Affiche ce menu d'aide."
    echo -e ""
    echo -e "Options de compilation (Engines):"
    echo -e "  -b,  --build <engine>     Compile un moteur (ex: ironwail)."
    echo -e "  -bf, --build-force <eng>  Purge le dossier source et relance une compilation propre."
    echo -e "  -lb, --list-builds        Liste tous les scripts de disponibles."
    echo -e ""
    echo -e "Options de distribution (Dist):"
    echo -e "  -lc, --list-creates       Liste toutes les recettes de variantes disponibles."
    echo -e "  -c,  --create <variant>   Créer une variante de jeu prête à jouer (ex: ironwail-ad)."
    echo -e ""
}

init_env() {
    echo -e ">>> [\e[1;34mINFO\e[0m] Initialisation de l'environnement OptiBox..."

    local dirs=(
        "$OB_DIST_DIR"
        "$OB_ASSETS_DIR"
        "$OB_LAUNCH_DIR"
        "$OB_LIBS_DIR"
        "$OB_ENGINES_DIR"
        "$OB_CORE_SRC"
        "$OB_CORE_LOG"
        "$OB_CORE_HELPERS"
        "$OB_CORE_SCRIPTS"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo -e " -> Créé : $dir"
        else
            echo -e " -> Existant : $dir"
        fi
    done

    echo -e ">>> [\e[1;32mSUCCESS\e[0m] Arborescence initialisée avec succès."
}

build_engine() {
    local target_script="$1"
    local script_path="${OB_CORE_SCRIPTS}/${target_script}.bld"

    echo -e ">>> [\e[1;34mINFO\e[0m] Demande de compilation : $target_script"

    # Vérification de l'existence du script
    if [ ! -f "$script_path" ]; then
        echo -e ">>> [\e[1;31mERREUR\e[0m] Script introuvable : $script_path"
        exit 1
    fi

    # Application des droits d'exécution
    chmod +x "$script_path" || {
      echo -e ">>> [\e[1;31mERREUR\e[0m] Impossible d'appliquer les droits d'exécution sur le script : $target_script"
      echo -e ">>> Vérifiez les permissions du dossier $OB_CORE_SCRIPTS."
      exit 1
    }

    # Exécution du script de build
    # On utilise "bash -c" ou l'appel direct pour l'isoler proprement
    "$script_path"

    local build_status=$?
    if [ $build_status -ne 0 ]; then
        echo -e ">>> [\e[1;31mERREUR\e[0m] Le build de $target_script s'est terminé avec une erreur."
        exit $build_status
    fi
}

build_force_engine() {
    local target_script="$1"

    echo -e ">>> [\e[1;33mWARN\e[0m] Mode FORCE activé pour $target_script"
    export OB_FORCE_BUILD=1           # Variable pour que "ob_build_check" force la compil. [SKIP]
    build_engine "$target_script"     # Demarrage du script de compilation
    unset OB_FORCE_BUILD              # On détruit la variable après coup pour ne pas forcer les autres builds
}

list_builds() {
    echo -e ">>> [\e[1;34mINFO\e[0m] Moteurs disponibles pour la compilation :"

    if [ ! -d "$OB_CORE_SCRIPTS" ] || [ -z "$(ls -A "$OB_CORE_SCRIPTS" 2>/dev/null)" ]; then
        echo -e "    \e[1;33mAucun script de build trouvé dans $OB_CORE_SCRIPTS\e[0m"
        return
    fi

    # On boucle sur tous les fichiers .bld et on formate la sortie
    for script in "$OB_CORE_SCRIPTS"/*.bld; do
        # Sécurité au cas où le dossier est vide (évite d'afficher "*.bld")
        [ -e "$script" ] || continue

        # On extrait juste le nom sans le chemin ni l'extension
        local script_name=$(basename "$script" .bld)
        echo -e "    - \e[1;36m$script_name\e[0m"
    done
    echo ""
}

create_variant() {
    local variant_name="$1"
    local recipe="${OB_CORE_VARIANTS}/${variant_name}.variant"

    ob_info "Demande de création de la variante : $variant_name"

    if [ ! -f "$recipe" ]; then
        ob_error "La recette $recipe est introuvable."
    fi

    # On purge l'environnement local pour éviter la fuite de variables entre deux créations
    unset GAME_LABEL GAME_DIR TARGET_ENGINE PK_EXT CONFIGS LAUNCH_PARAMS GAME_DESC SOURCES
    source "$recipe"

    local FULL_DEST="${OB_DIST_DIR}/${GAME_DIR}"
    local ENGINE_SRC="${OB_ENGINES_DIR}/${TARGET_ENGINE}"

    echo -e ">>> [\e[1;35mASSEMBLAGE\e[0m] $GAME_LABEL"

    # 1. RÉCUPÉRATION DU MOTEUR (Copie explicite)
    if [ -n "$TARGET_ENGINE" ] && [ -d "$ENGINE_SRC" ]; then
        ob_info "Copie du binaire depuis : $TARGET_ENGINE"
        mkdir -p "$FULL_DEST"
        rsync -a --exclude="*.info" "$ENGINE_SRC/" "$FULL_DEST/"
    else
        ob_error "Moteur introuvable dans $ENGINE_SRC. Compilez-le d'abord (-b $TARGET_ENGINE)."
    fi

    # 2. MERGE DES METADATAS GAME & ENGINE (.info -> .md)
    local ENGINE_INFO_FILE="$ENGINE_SRC/$(echo $TARGET_ENGINE | cut -d'-' -f1).info"
    local GAME_INFO_DEST="$FULL_DEST/info.md"

    ob_info "Génération des métadonnées: $(basename "$GAME_INFO_DEST")"
    {
        echo "# ${GAME_LABEL}"
        echo ""
        echo "$GAME_DESC"
        echo ""
        if [ -f "$ENGINE_INFO_FILE" ]; then
            cat "$ENGINE_INFO_FILE"
        fi
    } > "$GAME_INFO_DEST"

    # 3. LES ASSETS (liens symboliques)
    for entry in "${SOURCES[@]}"; do
        local SRC_SUB=$(echo "$entry" | cut -d':' -f1)
        local TGT_SUB=$(echo "$entry" | cut -d':' -f2)

        local CURRENT_SRC="${OB_ASSETS_DIR}/$SRC_SUB"
        local CURRENT_TGT="$FULL_DEST/$TGT_SUB"

        mkdir -p "$CURRENT_TGT"
        ob_info "Lien dynamique : $SRC_SUB -> $TGT_SUB"

        if [ -n "$PK_EXT" ]; then
            ln -sr "$CURRENT_SRC"/*."$PK_EXT" "$CURRENT_TGT/" 2>/dev/null
        else
            ln -sr "$CURRENT_SRC"/* "$CURRENT_TGT/" 2>/dev/null
        fi
    done

    # 4. CONFIGS JEU (Copie explicite des cfg si existantes)
    if [ -n "$CONFIGS" ]; then
        for cfg_entry in "${CONFIGS[@]}"; do
            local CFG_SRC_PATH=$(echo "$cfg_entry" | cut -d':' -f1)
            local CFG_TGT_SUB=$(echo "$cfg_entry" | cut -d':' -f2)

            local SRC_FILE="${OB_ASSETS_DIR}/$CFG_SRC_PATH"
            local TGT_PATH="$FULL_DEST/$CFG_TGT_SUB"

            mkdir -p "$TGT_PATH"
            ob_info "Synchronisation config : $(basename "$SRC_FILE") -> $CFG_TGT_SUB"
            cp -u "$SRC_FILE" "$TGT_PATH/"
        done
    fi

    local LAUNCH_FILE="${OB_LAUNCH_DIR}/game-${variant_name}"

    if [[ -f $LAUNCH_FILE ]]; then
        ob_info "Le launcher existe déjà : $(basename "$LAUNCH_FILE")"
    else
        ob_info "Génération du script de lancement : game-${variant_name}"

        # On utilise la variable GAME_EXE de la variante si elle existe,
        # sinon on déduit le nom depuis le moteur (fallback)
        local FINAL_EXE="${GAME_EXE:-$(echo $TARGET_ENGINE | cut -d'-' -f1)}"
        {
            echo "#!/bin/bash"
            echo "# OptiBox Launcher - $GAME_LABEL"
            echo "source \"${OB_LAUNCH_DIR}/${OB_LAUNCH_FILE}\""
            echo "cd \"$FULL_DEST\" || exit 1"

            # On injecte les paramètres seulement s'ils existent
            echo "./${FINAL_EXE} ${LAUNCH_PARAMS:-} \"\$@\""
        } > "$LAUNCH_FILE"

        chmod +x "$LAUNCH_FILE"
    fi

    ob_success "Variante $GAME_LABEL prête à jouer !"
}

list_variants() {
    echo -e ""
    echo -e ">>> [\e[1;34mINFO\e[0m] Recettes de variantes disponibles :"

    if [ ! -d "$OB_CORE_VARIANTS" ] || [ -z "$(ls -A "$OB_CORE_VARIANTS" 2>/dev/null)" ]; then
        echo -e "    \e[1;33mAucune recette trouvée dans $OB_CORE_VARIANTS\e[0m"
        return
    fi

    # Boucle sur les fichiers .variant
    for recipe in "$OB_CORE_VARIANTS"/*.variant; do
        [ -e "$recipe" ] || continue

        local variant_name=$(basename "$recipe" .variant)

        # Extraction du LABEL (sur une seule ligne, grep suffit)
        local game_label=$(grep "^GAME_LABEL=" "$recipe" | cut -d'"' -f2)

        # 2. Extraction du bloc GAME_DESC (multiligne) avec sed
        # - sed -n '/^GAME_DESC="/,/"$/p' : Copie tout depuis GAME_DESC=" jusqu'à la ligne qui se termine par "
        # - sed 's/^GAME_DESC="//; s/"$//' : Supprime la déclaration et le guillemet de fin
        # - grep -v "^#" : Ignore la ligne "## Description" pour aller droit au but
        # - tr '\n' ' ' : Transforme les retours à la ligne en espaces
        # - sed nettoie les espaces et blancs
        local main_desc=$(sed -n '/^GAME_DESC="/,/"$/p' "$recipe" | sed 's/^GAME_DESC="//; s/"$//' | grep -E -v "^#|^\*" | tr '\n' ' ' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # (on coupe proprement à 80 caractères)
        # local short_desc="${raw_desc:0:80}..."

        # Sécurité si le fichier n'a pas de description du tout
        if [ ${#main_desc} -eq 0 ]; then
            main_desc="Aucune description disponible."
        fi

        # Affichage
        echo -e "    - \e[1;36m${variant_name}\e[0m"
        echo -e "      \e[1;37m${game_label}\e[0m : \e[3;90m${main_desc}\e[0m"
    done
    echo ""
}

# --- PARSEUR D'ARGUMENTS ---

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -i|--init)
            init_env
            exit 0
            ;;
        -b|--build)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
               echo -e ">>> [\e[1;31mERREUR\e[0m] L'option --build nécessite le nom du script cible (ex: ironwail-master)."
               exit 1
            fi
            build_engine "$2"
            shift
            ;;
        -bf|--build-force)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
               echo -e ">>> [\e[1;31mERREUR\e[0m] L'option --build-force nécessite le nom du script cible."
               exit 1
            fi
            build_force_engine "$2"
            shift
            ;;
        -lb|--list-builds)
            list_builds
            exit 0
        ;;
        -c|--create)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
              echo -e ">>> [\e[1;31mERREUR\e[0m] L'option --create nécessite le nom d'une variante."
              exit 1
            fi
            create_variant "$2"
            shift
        ;;
        -lc|--list-creates)
            list_variants
            exit 0
        ;;
        *)
          echo -e ">>> [\e[1;31mERREUR\e[0m] Paramètre inconnu: $1"
          show_help
          exit 1
        ;;
    esac
    shift
done