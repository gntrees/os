FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# COSMIC build dependencies.
# If a package name moved in 26.04, the image build fails loudly here; adjust and
# record the change in docs/code-placement.txt only if placement is affected.
# `bsdextrautils` provides `rev`, used by cosmic-panel's `just install` recipe to
# place its default schema; without it the stage step silently installs nothing.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bsdextrautils \
      build-essential \
      ca-certificates \
      clang \
      cmake \
      curl \
      dbus \
      dbus-user-session \
      dbus-x11 \
      git \
      git-lfs \
      libclang-dev \
      libdav1d-dev \
      libdbus-1-dev \
      libdisplay-info-dev \
      libdrm-dev \
      libegl-dev \
      libexpat1-dev \
      libflatpak-dev \
      libfontconfig-dev \
      libfreetype-dev \
      libgbm-dev \
      libglvnd-dev \
      libgles-dev \
      libgstreamer-plugins-base1.0-dev \
      libgstreamer1.0-dev \
      libgtk-3-dev \
      libinput-dev \
      libpam0g-dev \
      libpipewire-0.3-dev \
      libpixman-1-dev \
      libpulse-dev \
      librsvg2-dev \
      libseat-dev \
      libssl-dev \
      libsoup-3.0-dev \
      libsystemd-dev \
      libudev-dev \
      libwayland-dev \
      libwebkit2gtk-4.1-dev \
      libxcb1-dev \
      libxkbcommon-dev \
      libxkbcommon-x11-dev \
      lld \
      meson \
      mold \
      nasm \
      ninja-build \
      pkg-config \
      rsync \
      wayland-protocols \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's rustc is too old for COSMIC 1.11.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain stable

# `just` from stable: the packaged version may not support `mod` used upstream.
RUN cargo install just --locked

# Runtime libraries for `just preview`.
RUN apt-get update && apt-get install -y --no-install-recommends \
      adwaita-icon-theme \
      fonts-noto-core \
      fonts-open-sans \
      hicolor-icon-theme \
      libdav1d7 \
      libdisplay-info3 \
      libegl-mesa0 \
      libegl1 \
      libgbm1 \
      libgl1-mesa-dri \
      libgles2 \
      libgstreamer-plugins-base1.0-0 \
      libgstreamer1.0-0 \
      libinput10 \
      libpam0g \
      libpipewire-0.3-0 \
      libpixman-1-0 \
      libpulse0 \
      libseat1 \
      libwayland-client0 \
      libwayland-egl1 \
      libwayland-server0 \
      libxcb1 \
      libxkbcommon0 \
      mesa-vulkan-drivers \
      polkitd \
      xwayland \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
CMD ["/bin/bash"]
