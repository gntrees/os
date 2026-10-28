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

# Install build output into the staging rootfs.
stage:
    @bash scripts/stage.sh

# Run the COSMIC session nested on the host desktop.
preview:
    @bash scripts/preview.sh

# Build the live ISO from the staged rootfs.
iso:
    @bash scripts/iso.sh

# Copy the built ISO to the Ventoy USB and flush it, with progress.
usb mount="":
    @bash scripts/usb.sh "{{mount}}"

# Remove rootfs, live build tree, and ISO output.
clean:
    @bash scripts/clean.sh

# Screenshots land in ~/.cache/gntress-os/cache/vm.
# disk=<GiB> adds a blank target disk; vnc=1 publishes 127.0.0.1:5901.
# Boot the built ISO in a KVM VM and capture screenshots.
vm iso="" mode="uefi" seconds="120" login="0" install="0" disk="0" vnc="0":
    @bash scripts/vm.sh "{{iso}}" "{{mode}}" "{{seconds}}" "{{login}}" "{{install}}" "{{disk}}" "{{vnc}}"
