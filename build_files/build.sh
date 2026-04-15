#!/usr/bin/bash
set -ouex pipefail

# Enable vanilla-next kernel repo
dnf5 -y copr enable @kernel-vanilla/next

# Make sure none of the akmods/matched-kernel baggage survives into this image
for pkg in kernel-modules-akmods kernel-devel-matched akmods dkms; do
    if rpm -q "${pkg}"; then
        dnf5 -y remove "${pkg}"
    fi
done

# Actually switch the installed kernel stack to the newest available build
dnf5 -y distro-sync \
    kernel \
    kernel-core \
    kernel-modules \
    kernel-modules-core \
    kernel-modules-extra

dnf5 -y install \
    kernel-devel \
    kernel-headers

KVER="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)"
dracut --force --kver "$KVER" --add ostree
lsinitrd "/boot/initramfs-${KVER}.img" | grep -E 'ostree|prepare-root|sysroot'

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
    fish \
    distrobox \
    pipewire \
    wireplumber \
    pipewire-alsa \
    pipewire-pulseaudio \
    pipewire-utils \
    alsa-utils \
    pavucontrol \
    rtkit \
    xdg-desktop-portal \
    xdg-desktop-portal-wlr

# Keep the example service if you want it, otherwise remove this
systemctl enable podman.socket

# Cleanup
dnf5 clean all

echo "=== installed kernel packages ==="
rpm -q kernel kernel-core kernel-modules kernel-devel kernel-headers || true

echo "=== loader entries under /boot ==="
find /boot/loader/entries -maxdepth 1 -type f -print -exec sed -n '1,120p' {} \; 2>/dev/null || true

echo "=== ostree boot entries under /usr/lib/ostree-boot ==="
find /usr/lib/ostree-boot -type f -print -exec sed -n '1,120p' {} \; 2>/dev/null || true

echo "=== grep for ostree kernel arg ==="
grep -R "ostree=" /boot/loader/entries /usr/lib/ostree-boot 2>/dev/null || true
