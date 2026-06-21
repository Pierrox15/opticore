# ==============================================================================
# SCRIPT DE POST-INSTALLATION AUTOMATISÉE - OPTIBOX (Debian 13)
# Optimisation Low-Latency / Bare-Metal pour Core 2 Quad & Xeon LGA775
# ==============================================================================

# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Erreur : Ce script doit être exécuté en tant que root."
  exit 1
fi

echo "=================================================================="
echo "      DÉBUT DE L'INSTALLATION DE LA CONFIGURATION OPTIBOX         "
echo "=================================================================="

# ------------------------------------------------------------------------------
# 0. Configuration du dépôt NVIDIA CUDA (Derniers pilotes 580+)
# ------------------------------------------------------------------------------
echo "[*] Configuration du dépôt officiel NVIDIA avec bypass de clé GPG..."

# Écriture directe avec le flag trusted=yes suite aux erreurs de clé du dépôt
cat << 'EOF' > /etc/apt/sources.list.d/cuda-debian12-x86_64.list
deb [trusted=yes] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /
EOF

echo "[OK] Dépôt NVIDIA configuré en mode de confiance forcé."

echo "[*] Installation du paquet d'épinglage pour la branche NVIDIA 580..."

# On met à jour l'index après l'ajout du dépôt, puis on installe le paquet de pinning
dpkg --add-architecture i386
apt-get update
apt-get install -y nvidia-driver-pinning-580

echo "[OK] Branche 580 verrouillée nativement par APT."


echo "[*] Installation des pilotes NVIDIA et des composants associés..."

# Désormais, APT sait qu'il doit tirer uniquement la version 580 de ces paquets

apt-get update

# 2. La commande d'installation corrigée
apt-get install -y \
    nvidia-driver \
    nvidia-driver-libs:i386 \
    nvidia-kernel-dkms \
    nvidia-persistenced \
    vulkan-tools \
    libvulkan1 \
    libvulkan1:i386

echo "[OK] Pilotes NVIDIA 580 installés avec succès."

# Nettoyage des services "inutiles" dans un contexte de performance jeu pure
apt-get purge -y wpasupplicant accountsservice
apt-get purge -y connman connman-vpn exim4 exim4-base exim4-config exim4-daemon-light udisks2 upower
apt-get autoremove --purge -y

sudo apt-get purge -y \
    pulseaudio \
    pulseaudio-utils \
    pipewire \
    pipewire-bin \
    pipewire-audio-client-libraries \
    wireplumber

apt-get autoremove --purge -y



# ------------------------------------------------------------------------------
# 1. Configuration des modules NVIDIA (/etc/modprobe.d/nvidia.conf)
# ------------------------------------------------------------------------------
echo "[*] Configuration des options du module NVIDIA..."
mkdir -p /etc/modprobe.d
cat << 'EOF' > /etc/modprobe.d/nvidia.conf
# Désactivation du pilote open-source
blacklist nouveau

# Optimisations mémoire, alimentation et performance brute
options nvidia NVreg_TemporaryFilePath=/var/tmp
options nvidia NVreg_EnableS0ixPowerManagement=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_RegistryDwords="RmEnableAggressiveVblank=1; PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerDefaultAC=0x1"
EOF
echo "[OK] /etc/modprobe.d/nvidia.conf configuré."

# ------------------------------------------------------------------------------
# 2. Optimisations Sysctl (/etc/sysctl.d/99-optibox.conf)
# ------------------------------------------------------------------------------
echo "[*] Application des optimisations Sysctl (gestion des IRQ)..."
mkdir -p /etc/sysctl.d
cat << 'EOF' > /etc/sysctl.d/99-optibox.conf
# Empêche le throttle des interruptions lors des pics de charge
kernel.perf_event_max_sample_rate=100000
kernel.perf_cpu_time_max_percent=25
EOF
sysctl --system > /dev/null
echo "[OK] Sysctl mis à jour."

# ------------------------------------------------------------------------------
# 3. Configuration GRUB (avec correction du polling USB et fbdev)
# ------------------------------------------------------------------------------
echo "[*] Configuration de la ligne de commande GRUB..."
# On injecte tes options de polling USB ici, là où elles sont valides et effectives
GRUB_OPTS="nvidia-drm.modeset=1 intel_iommu=off hpet=disable pcie_aspm=off threadirqs skew_tick=1 kvm.ignore_msrs=1 mitigations=off apparmor=0 fbcon=nodefer nvidia-drm.fbdev=1 usbhid.jspoll=1 usbhid.mousepoll=1 video=DP-3:1920x1200@100"

if [ -f /etc/default/grub ]; then
    # Sauvegarde de sécurité
    cp /etc/default/grub /etc/default/grub.bak
    # Remplacement de la ligne GRUB_CMDLINE_LINUX_DEFAULT
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_OPTS\"|" /etc/default/grub
    update-grub
    echo "[OK] GRUB mis à jour avec les paramètres de latence et polling USB."
else
    echo "[!] Attention : /etc/default/grub introuvable. GRUB n'a pas été configuré."
fi

# ------------------------------------------------------------------------------
# 4. Activation des services de gestion d'énergie NVIDIA
# ------------------------------------------------------------------------------
echo "[*] Activation des services système NVIDIA pour la mise en veille..."
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null
echo "[OK] Services NVIDIA activés."

# ------------------------------------------------------------------------------
# 5. Purge complète de zram (Évite le swap logiciel/compression CPU)
# ------------------------------------------------------------------------------
echo "[*] Désactivation et suppression de zram..."
swapoff /dev/zram0 2>/dev/null
systemctl stop zramswap.service 2>/dev/null
systemctl disable zramswap.service 2>/dev/null
apt-get purge -y zram-tools zram-config zramswap-enabler > /dev/null 2>&1
echo "[OK] zram totalement purgé du système."

# ------------------------------------------------------------------------------
# 6. Écriture du Script d'Affinité IRQ (/usr/local/sbin/opti-affinity.sh)
# ------------------------------------------------------------------------------
echo "[*] Déploiement du script d'affinité IRQ optimisé par Die..."
mkdir -p /usr/local/sbin

cat << 'EOF' > /usr/local/sbin/opti-affinity.sh
#!/bin/bash
# -------------------------------------------------------------------------
# OPTIBOX: CONFIGURATION UNIVERSELLE (Xeon/Core2Quad + Quadro)
# OPTIMISÉE POUR : RAID0 / Latence Minimale / Répartition par Die
# -------------------------------------------------------------------------

echo "--- Initialisation de l'affinité des IRQ (Mode Bare-Metal) ---"

# 1. Neutralisation de l'ordonnanceur automatique
systemctl stop irqbalance 2>/dev/null
echo "[OK] Service irqbalance stoppé pour éviter les conflits d'affinité."

# 2. Identification des IRQ
GPU_IRQ=$(grep -i "nvidia" /proc/interrupts | awk '{print $1}' | sed 's/://' | head -n 1)
SSD_IRQ=$(grep -i "ahci" /proc/interrupts | awk '{print $1}' | sed 's/://' | head -n 1)
SND_IRQ=$(grep -i "snd_hda_intel" /proc/interrupts | awk '{print $1}' | sed 's/://' | head -n 1)

# 3. Isolation GPU (Die 1 - Cœur 0)
if [ -n "$GPU_IRQ" ]; then
    echo 1 > /proc/irq/$GPU_IRQ/smp_affinity
    echo "[OK] NVIDIA (IRQ $GPU_IRQ) -> Coeur 0 (Die 1)"
    # Assigne les processus NVIDIA sur le Die 1 (Cœurs 0,1)
    for pid in $(pgrep -f nvidia); do
        taskset -pa -c 0,1 $pid > /dev/null 2>&1
    done
fi

# 4. Isolation Stockage AHCI (Die 2 - Cœur 3)
if [ -n "$SSD_IRQ" ]; then
    echo 8 > /proc/irq/$SSD_IRQ/smp_affinity
    echo "[OK] Stockage AHCI (IRQ $SSD_IRQ) -> Coeur 3 (Die 2)"
    # On force le journal du système de fichiers sur le même Die (Cœurs 2,3)
    pgrep -f jbd2 | xargs -r -I {} taskset -pc 2,3 {} > /dev/null 2>&1
fi

# 5. Isolation AUDIO (Die 1 - Cœur 1)
#if [ -n "$SND_IRQ" ]; then
#    echo 2 > /proc/irq/$SND_IRQ/smp_affinity
#    echo "[OK] Audio Intel (IRQ $SND_IRQ) -> Coeur 1 (Die 1)"
#    # Priorité Temps Réel pour le serveur de son
#    pgrep -f "pipewire|wireplumber|pulseaudio" | xargs -r -I {} chrt -f -p 85 {} > /dev/null 2>&1
#    pgrep -f "pipewire|wireplumber|pulseaudio" | xargs -r -I {} taskset -pc 1 {} > /dev/null 2>&1
#fi

# 6. Mode Performance CPU
if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
    echo "performance" | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
    echo "[OK] Gouverneur CPU -> Performance"
else
    echo "[!] Scaling CPU non géré par le noyau (EIST probablement OFF dans le BIOS)."
fi

# 7. Activation du réveil USB
for dev in /sys/bus/usb/devices/*/power/wakeup; do
    [ -f "$dev" ] && echo "enabled" > "$dev" 2>/dev/null
done
echo "[OK] Ports USB configurés pour le réveil du système."
EOF

# Attribution des droits d'exécution au script d'affinité
chmod +x /usr/local/sbin/opti-affinity.sh
echo "[OK] Script d'affinité rendu exécutable."

# ------------------------------------------------------------------------------
# 7. Création et activation du Service Systemd
# ------------------------------------------------------------------------------
echo "[*] Création du service systemd 'optibox-init'..."

cat << 'EOF' > /etc/systemd/system/optibox-init.service
[Unit]
Description=Optimisation des IRQ et Affinites OptiBox
After=local-fs.target nvidia-persistenced.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/opti-affinity.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Rechargement et activation du service
systemctl daemon-reload
systemctl enable optibox-init.service
echo "[OK] Service systemd activé au démarrage."

echo "=================================================================="
echo "    INSTALLATION TERMINÉE ! VEUILLEZ REDÉMARRER LA MACHINE.       "
echo "=================================================================="