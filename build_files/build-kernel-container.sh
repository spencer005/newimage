#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$HOME/tmp/newimage/build_files}"
OUT="${OUT:-$ROOT/rpms}"
SRPM="${SRPM:-$ROOT/copr-src/kernel-7.1.0-0.0.next.20260414.262.vanilla.fc43.src.rpm}"

if [[ ! -f "$SRPM" ]]; then
  echo "missing SRPM: $SRPM" >&2
  echo "download it with:" >&2
  echo "  curl -L -o $SRPM https://download.copr.fedorainfracloud.org/results/@kernel-vanilla/next/fedora-43-x86_64/Packages/k/kernel-7.1.0-0.0.next.20260414.262.vanilla.fc43.src.rpm" >&2
  exit 1
fi

mkdir -p "$OUT"

echo "[host] building kernel from SRPM: $SRPM"
echo "[host] output RPM dir: $OUT"

podman run --rm -t \
  -v "$SRPM:/src/kernel.src.rpm:Z" \
  -v "$OUT:/out:Z" \
  docker.io/fedora:43 \
  bash -lc '
set -euo pipefail

WORK=/work
TOPDIR=$WORK/rpmbuild
mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

dnf -y install dnf-plugins-core rpm-build rpmdevtools \
  gcc gcc-c++ make clang llvm lld binutils \
  rust rust-src python3 perl git rsync >/dev/null

# Pull full build dependencies from SRPM metadata.
dnf -y builddep /src/kernel.src.rpm >/dev/null

rpm -Uvh --define "_topdir $TOPDIR" /src/kernel.src.rpm >/dev/null

find "$TOPDIR/SOURCES" -type f -name "kernel-*.config" -print0 |
  xargs -0r sed -i \
    -e "s/^CONFIG_CRYPTO_USER_API_AEAD=.*/# CONFIG_CRYPTO_USER_API_AEAD is not set/" \
    -e "s/^CONFIG_NTSYNC=.*/CONFIG_NTSYNC=m/" \
    -e "s/^# CONFIG_NTSYNC is not set/CONFIG_NTSYNC=m/"

if ! grep -q "^CONFIG_NTSYNC=m$" "$TOPDIR/SOURCES/kernel-x86_64-fedora.config"; then
  echo "CONFIG_NTSYNC was not enabled in the x86_64 Fedora kernel config." >&2
  exit 1
fi

rpmbuild -ba "$TOPDIR/SPECS/kernel.spec" \
  --define "_topdir $TOPDIR" \
  --target x86_64

find "$TOPDIR/RPMS" -type f -name "kernel-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-core-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-modules-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-modules-core-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-modules-extra-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-devel-*.rpm" -print -exec cp -f {} /out/ \;
find "$TOPDIR/RPMS" -type f -name "kernel-headers-*.rpm" -print -exec cp -f {} /out/ \;
'

echo "[host] done. copied RPMs to $OUT"
ls -lh "$OUT" | sed -n '1,200p'
