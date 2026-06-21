#!/bin/bash

source "$(dirname "$0")/global.conf"

clean_links() {
    local target_dir=$1
    if [ -d "$target_dir" ]; then
        echo "Nettoyage des liens dans $target_dir..."
        find "$target_dir" -maxdepth 1 -type l -delete
    fi
}

run_link() {
    local recipe="$MANIFEST_DIR/$1.lnk" # Correction LNK_DIR -> MANIFEST_DIR

    if [ -f "$recipe" ]; then
        unset GAME_DIR SOURCES PK_EXT CONFIGS ENGINE LAUNCH_PARAMS
        source "$recipe"

        local FULL_DEST="$DIST_DIR/$GAME_DIR"
        local ENGINE_SRC="$ENGINES_DIR/$ENGINE"

        echo ">>> ASSEMBLAGE : $GAME_LABEL"

        # RÉCUPÉRATION DU MOTEUR (Copie explicite)
        if [ -n "$ENGINE" ] && [ -d "$ENGINE_SRC" ]; then
            echo "  [engine] Copie du moteur depuis : $ENGINE_SRC"
            mkdir -p "$FULL_DEST"
            # rsync préserve les permissions d'exécution du Yorkfield
            rsync -a --exclude="/${ENGINE}.info" "$ENGINE_SRC/" "$FULL_DEST/"
        else
            echo "  [ERREUR] Moteur introuvable dans $ENGINE_SRC"
        fi

        # MERGE DES METADATAS GAME & ENGINE (.info)
        local ENGINE_INFO_FILE="$ENGINE_SRC/${ENGINE}.info"
        local GAME_INFO_DEST="$FULL_DEST/info.md"

        echo "  [metadata] Génération: $(basename "$GAME_INFO_DEST")"
        {
            echo "# ${GAME_LABEL}"
            echo " "
            echo "$GAME_DESC"
            if [ -f "$ENGINE_INFO_FILE" ]; then
                cat "$ENGINE_INFO_FILE"
            fi
        } > "$GAME_INFO_DEST"

        # LES ASSETS (liens symboliques)
        for entry in "${SOURCES[@]}"; do
            SRC_SUB=$(echo "$entry" | cut -d':' -f1)
            TGT_SUB=$(echo "$entry" | cut -d':' -f2)

            local CURRENT_SRC="$ASSETS_DIR/$SRC_SUB"
            local CURRENT_TGT="$FULL_DEST/$TGT_SUB"

            mkdir -p "$CURRENT_TGT"
            #clean_links "$CURRENT_TGT"

            echo "  [link] $SRC_SUB -> $TGT_SUB"
            if [ -n "$PK_EXT" ]; then
                ln -sr "$CURRENT_SRC"/*."$PK_EXT" "$CURRENT_TGT/" 2>/dev/null
            else
                ln -sr "$CURRENT_SRC"/* "$CURRENT_TGT/" 2>/dev/null
            fi
        done

        # CONFIGS JEU (Copie explicite des cfg)
        if [ -n "$CONFIGS" ]; then
            for cfg_entry in "${CONFIGS[@]}"; do
                CFG_SRC_PATH=$(echo "$cfg_entry" | cut -d':' -f1)
                CFG_TGT_SUB=$(echo "$cfg_entry" | cut -d':' -f2)

                local SRC_FILE="$ASSETS_DIR/$CFG_SRC_PATH"
                local TGT_PATH="$FULL_DEST/$CFG_TGT_SUB"

                mkdir -p "$TGT_PATH"
                echo "  [sync] $(basename "$SRC_FILE") -> $CFG_TGT_SUB"

                # On utilise cp -u pour ne mettre à jour que si la source est plus récente
                cp -u "$SRC_FILE" "$TGT_PATH/"
            done
        fi

        # GÉNÉRATION DU LANCEUR
        if [ -n "$LAUNCH_PARAMS" ]; then
            local LAUNCH_FILE="$LAUNCH_DIR/$1"
            echo "  [launch] Génération : $1"

            # On écrit ligne par ligne
            {
                echo "#!/bin/bash"
                echo "# OptiBox Launcher - $GAME_LABEL"
                echo "source \"$LAUNCH_HEADER\""
                echo "cd \"$FULL_DEST\" || exit 1"
                echo "./${GAME_EXE:-$ENGINE} $LAUNCH_PARAMS \"\$@\""
            } > "$LAUNCH_FILE"

            chmod +x "$LAUNCH_FILE"
        fi
        echo ">>> Terminé."

    else
        echo "Erreur : La recette $recipe est introuvable."
    fi
}

# --- LOGIQUE D'APPEL ---
case "$1" in
    "-all")
        for f in "$MANIFEST_DIR"/*.lnk; do
            run_link "$(basename "$f" .lnk)"
        done
        ;;
    "")
        echo "Usage: $0 {nom_recette|-all}"
        exit 1
        ;;
    *)
        run_link "$1"
        ;;
esac