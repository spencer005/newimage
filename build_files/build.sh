#!/usr/bin/bash
set -ouex pipefail

LOCAL_KERNEL_RPM_DIR="/ctx/rpms"
KERNEL_SOURCE="copr"

# Make sure none of the akmods/matched-kernel baggage survives into this image
for pkg in kernel-modules-akmods kernel-devel-matched akmods dkms; do
    if rpm -q "${pkg}"; then
        dnf5 -y remove "${pkg}"
    fi
done

# hack
if [ -e /usr/lib/kernel/install.d/50-depmod.install ]; then
    ln -sf 50-depmod.install /usr/lib/kernel/install.d/01-depmod.install
fi

if ls "${LOCAL_KERNEL_RPM_DIR}"/kernel-core-*.rpm >/dev/null 2>&1; then
    echo "=== using locally built kernel RPMs from ${LOCAL_KERNEL_RPM_DIR} ==="
    KERNEL_SOURCE="local-rpm"
    dnf5 -y install --allowerasing \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-[0-9]*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-core-*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-modules-*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-modules-core-*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-modules-extra-*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-devel-*.rpm \
        "${LOCAL_KERNEL_RPM_DIR}"/kernel-headers-*.rpm
else
    echo "=== using COPR kernel-vanilla/next packages ==="
    dnf5 -y copr enable @kernel-vanilla/next

    dnf5 -y distro-sync \
        kernel \
        kernel-core \
        kernel-modules \
        kernel-modules-core \
        kernel-modules-extra

    dnf5 -y install \
        kernel-devel \
        kernel-headers
fi

KVER="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n1)"

if grep -q '^CONFIG_CRYPTO_USER_API_AEAD=y$' "/usr/lib/modules/${KVER}/config"; then
    echo "CONFIG_CRYPTO_USER_API_AEAD is built in; CopyFail cannot be mitigated with modprobe.d." >&2
    echo "Rebuild the kernel with CONFIG_CRYPTO_USER_API_AEAD disabled or modular." >&2
    if [ "${KERNEL_SOURCE}" = "local-rpm" ]; then
        exit 1
    fi
fi

# bootc images should not ship kernel/initramfs in /boot
#rm -f /boot/initramfs-* /boot/vmlinuz-* || true

# regenerate initramfs in the canonical bootc location
#dracut --force --add ostree "/usr/lib/modules/${KVER}/initramfs.img" "${KVER}"

test -e "/usr/lib/modules/${KVER}/vmlinuz"
test -e "/usr/lib/modules/${KVER}/initramfs.img"

ls -lh "/usr/lib/modules/${KVER}/vmlinuz" "/usr/lib/modules/${KVER}/initramfs.img"

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

# Use sudo-rs without shipping the classic sudo package. The Fedora sudo-rs
# package intentionally installs sudo-rs/visudo-rs, so provide the familiar
# command names after removing sudo.
dnf5 -y install sudo-rs
rm -f \
    /etc/dnf/protected.d/sudo.conf \
    /usr/etc/dnf/protected.d/sudo.conf \
    /usr/share/dnf5/libdnf.conf.d/protect-sudo.conf
dnf5 -y remove --no-autoremove sudo

install -d -m 0750 -o root -g root /etc/sudoers.d
cat > /etc/sudoers <<'EOF'
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/bin"
root ALL=(ALL:ALL) ALL
@includedir /etc/sudoers.d
EOF
cat > /etc/sudoers.d/00-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
chown root:root /etc/sudoers /etc/sudoers.d/00-wheel
chmod 0440 /etc/sudoers /etc/sudoers.d/00-wheel

install -d -m 0755 -o root -g root /etc/pam.d
cat > /etc/pam.d/sudo <<'EOF'
#%PAM-1.0
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    optional     pam_keyinit.so revoke
session    required     pam_limits.so
session    include      system-auth
EOF
cat > /etc/pam.d/sudo-i <<'EOF'
#%PAM-1.0
auth       include      sudo
account    include      sudo
password   include      sudo
session    optional     pam_keyinit.so force revoke
session    include      sudo
EOF

/usr/bin/visudo-rs --check /etc/sudoers
ln -sf /usr/bin/sudo-rs /usr/bin/sudo
ln -sf /usr/bin/visudo-rs /usr/bin/visudo

# DirtyFrag mitigation: install directives block manual and dependency loads.
install -d -m 0755 -o root -g root /usr/lib/modprobe.d
cat > /usr/lib/modprobe.d/dirtyfrag.conf <<'EOF'
install esp4 /bin/false
install esp6 /bin/false
install rxrpc /bin/false
install algif_aead /bin/false
EOF

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

rm -rf /tmp/* /var/tmp/* || true
