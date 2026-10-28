#!/bin/sh
# Runs inside the freshly unpacked target, as root, before the bootloader is
# installed. Turns the live image into a normal installed system.
set -eu

export DEBIAN_FRONTEND=noninteractive

# live-boot/live-config would make the installed system try to boot as a live
# medium. Purge them one by one: a single unknown package name must not abort
# the whole purge and leave the system live-booting.
for pkg in live-boot live-boot-initramfs-tools live-config live-config-systemd; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        apt-get -y purge "$pkg" || true
    fi
done

# live-config creates this account at runtime and grants it sudo; neither may
# survive into the installed system.
rm -rf /home/user
rm -f /etc/sudoers.d/live /etc/sudoers.d/user

# The COSMIC session entry point must stay available after the purge.
systemctl enable greetd.service || true

# Rebuild the initramfs now that the live hooks are gone.
update-initramfs -u -k all || true

# Regenerate the boot menu with the target's kernel and initrd.
update-grub || true
