FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      live-build \
      debootstrap \
      squashfs-tools \
      xorriso \
      isolinux \
      syslinux-common \
      syslinux-utils \
      grub-pc-bin \
      grub-efi-amd64-bin \
      mtools \
      dosfstools \
      rsync \
      ca-certificates \
      xz-utils \
      zstd \
      file \
      wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
CMD ["/bin/bash"]
