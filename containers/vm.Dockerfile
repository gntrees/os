FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# QEMU plus OVMF for UEFI. socat drives the QEMU monitor so the harness can
# take screenshots without a graphical session on the host.
RUN apt-get update && apt-get install -y --no-install-recommends \
      qemu-system-x86 \
      qemu-utils \
      ovmf \
      socat \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /vm
CMD ["/bin/bash"]
