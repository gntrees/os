set shell := ["bash", "-euo", "pipefail", "-c"]

# Show available recipes.
default:
    @just --list

# Check host prerequisites (docker, disk, filesystem, RAM).
doctor:
    @bash scripts/doctor.sh

# Clone active components at the commits pinned in versions.lock.
fetch:
    @bash scripts/fetch.sh

# Compile components inside the Ubuntu build container.
build:
    @bash scripts/build.sh

# Download and verify the external app artifacts pinned in vendor.lock.
vendor:
    @bash scripts/vendor.sh

# Build the launcher and install it into the staging rootfs.
app:
    @bash scripts/app.sh

# Build the .deb packages from the staged rootfs and repo sources.
deb:
    @bash scripts/deb.sh

# Build the APT repo tree from .deb files (needs GNTREES_SIGN_KEYFILE).
repo:
    @bash scripts/repo.sh

# Upload the signed APT tree and the ISOs to R2. Needs GNTREES_PUBLISH_REMOTE.
publish:
    @bash scripts/publish.sh

# Install build output into the staging rootfs.
stage:
    @bash scripts/stage.sh

# Run the COSMIC session nested on the host desktop.
preview:
    @bash scripts/preview.sh

# Build the live ISO from the staged rootfs; pulls gntrees-os-release from the published repo.
# Skips the build when the inputs are unchanged; set GNTREES_FORCE_ISO=1 to force.
iso:
    @bash scripts/iso.sh

# Copy the built ISO to the Ventoy USB and flush it, with progress.
usb mount="":
    @bash scripts/usb.sh "{{mount}}"

# Remove rootfs, live build tree, ISO output, .deb packages, and the APT tree.
clean:
    @bash scripts/clean.sh

# Both recipes expose VNC on 127.0.0.1:5901 and keep screenshots off. Every
# setting is optional and comes from the environment:
#   GNTREES_VM_ISO=<file>    default: out/<name>-<version>-<arch>.iso
#   GNTREES_VM_DISK=<GiB>    default: 24 (dibuat bila belum ada)
#   GNTREES_VM_FRESH=1       buang isi disk lalu buat baru
#   GNTREES_VM_SECONDS=<n>   default: 900; 0 = sampai Ctrl+C
#   GNTREES_VM_VNC=0         matikan VNC
#   GNTREES_VM_SHOTS=1       screenshot tiap 15 s ke cache/vm
#   GNTREES_VM_MODE=bios     firmware legacy
# Boot the live ISO straight into the installer kiosk, with a target disk, over
# VNC. There is no login prompt or desktop preview on the live medium.
vm-live:
    @GNTREES_VM_BOOT=live GNTREES_VM_VNC="${GNTREES_VM_VNC:-1}" GNTREES_VM_DISK="${GNTREES_VM_DISK:-24}" bash scripts/vm.sh

# Boot the installed system from that disk up to the login screen, over VNC.
vm-installed:
    @GNTREES_VM_BOOT=installed GNTREES_VM_VNC="${GNTREES_VM_VNC:-1}" GNTREES_VM_DISK="${GNTREES_VM_DISK:-24}" bash scripts/vm.sh
