#!/usr/bin/bash
set -ouex pipefail

# Enable vanilla-next kernel repo
dnf5 -y copr enable group_kernel-vanilla/next

# Make sure none of the akmods/matched-kernel baggage survives into this image
for pkg in kernel-modules-akmods kernel-devel-matched akmods dkms; do
    if rpm -q "${pkg}"; then
        dnf5 -y remove "${pkg}"
    fi
done

# Pull the kernel stack from the vanilla-next COPR
dnf5 -y install \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra \
    kernel-devel

# Minimal stuff you probably still want on a self-managed WM system
dnf5 -y install \
    git \
    gcc \
    gcc-c++ \
    clang \
    make \
    cmake \
    meson \
    ninja-build \
    pkgconf-pkg-config \
    wayland-devel \
    wayland-protocols-devel \
    libxkbcommon-devel \
    pixman-devel \
    cairo-devel \
    pango-devel \
    seatd \
    wl-clipboard \
    foot \
    tmux \
    fish

# Keep the example service if you want it, otherwise remove this
systemctl enable podman.socket

# Cleanup
dnf5 clean all
