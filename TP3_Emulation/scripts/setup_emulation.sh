#!/bin/bash
# Script de mise en place de l'émulation QEMU ARM
# Usage: sudo bash setup_emulation.sh <chemin_squashfs_root>

ROOTFS=${1:-"./squashfs-root"}

echo "[*] Installation de qemu-arm-static dans le rootfs..."
cp /usr/bin/qemu-arm-static "$ROOTFS/usr/bin/"

echo "[*] Montage des pseudo-systèmes de fichiers..."
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount -o bind /dev "$ROOTFS/dev"

echo "[*] Création des répertoires manquants..."
mkdir -p "$ROOTFS/var/run" "$ROOTFS/var/log" "$ROOTFS/tmp/www" "$ROOTFS/tmp/config"

echo "[+] Environnement prêt. Pour entrer dans le chroot :"
echo "    sudo chroot $ROOTFS /usr/bin/qemu-arm-static /bin/sh"
echo ""
echo "[+] Pour lancer httpd :"
echo "    sudo chroot $ROOTFS /usr/bin/qemu-arm-static /usr/sbin/httpd"
