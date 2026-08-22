#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

dnf install -y dnf-plugins-core

dnf copr enable -y egergo/mine

KERNEL="$(ls /usr/lib/modules)"

dnf install -y --setopt=tsflags=nodocs \
    code \
    distrobox \
    krb5-workstation \
    kvantum \
    virt-manager \
    wireshark \
    zsh \
    strace \
    ncdu

### Build or reuse the nct6687d akmod
# akmods runs rpmbuild internally, stamping BUILDTIME=now on every run, which
# churns the entire layer containing the module. Reuse a previously built rpm
# (restored by CI cache) whenever it targets the running kernel so routine
# builds produce byte-identical output.
CACHE_DIR="${KMOD_CACHE_DIR:-/tmp/kmod-cache}"
mkdir -p "${CACHE_DIR}"
KMOD_RPM="${CACHE_DIR}/kmod-nct6687d-${KERNEL}.rpm"

kmod_cached() {
  [[ -s "${KMOD_RPM}" ]] || return 1
  [[ "$(rpm -qp --qf '%{NAME}' "${KMOD_RPM}" 2>/dev/null)" == kmod-nct6687d* ]]
}

if kmod_cached \
  && dnf install -y --setopt=tsflags=noscripts "${KMOD_RPM}" \
  && [[ -e "/usr/lib/modules/${KERNEL}/extra/nct6687d/nct6687.ko.xz" ]]; then
  echo "Reusing cached akmod: ${KMOD_RPM}"
else
  # akmods hard-requires kernel-devel-matched, which pulls the latest kernel
  # pair from the updates repo. Let it happen and build for whatever kernel
  # we end up shipping, then make sure devel matches that exact version.
  dnf install -y --setopt=tsflags=noscripts \
      akmods \
      kmodtool \
      gcc \
      make \
      nct6687d

  KERNEL="$(ls /usr/lib/modules)"
  KMOD_RPM="${CACHE_DIR}/kmod-nct6687d-${KERNEL}.rpm"

  if ! rpm -q kernel-devel-${KERNEL} &>/dev/null; then
    KD_ARCH="${KERNEL##*.}"           # x86_64
    KD_REL="${KERNEL#*-}"             # 200.fc44.x86_64
    KD_REL="${KD_REL%."${KD_ARCH}"}"  # 200.fc44
    KD_VER="${KERNEL%%-*}"            # 7.1.8

    dnf install -y --setopt=tsflags=noscripts "kernel-devel-${KERNEL}" || \
      dnf install -y --setopt=tsflags=noscripts \
        "https://kojipkgs.fedoraproject.org/packages/kernel/${KD_VER}/${KD_REL}/${KD_ARCH}/kernel-devel-${KERNEL}.rpm"
  fi

  akmods --force --kernels "${KERNEL}"

  cp "$(find /var/cache/akmods -name 'kmod-nct6687d-*.rpm' | head -1)" "${KMOD_RPM}"
fi

if rpm -q kernel-devel-${KERNEL} &>/dev/null; then
  dnf remove -y kernel-devel-${KERNEL} gcc make
fi
dnf clean all

sed -i 's/Kinoite/BrOS/g' /usr/lib/os-release

### Remove build-state files that would otherwise differ on every build
# and invalidate the layers containing them
rm -fv /var/lib/dnf/repos/*/countme
rm -fv /usr/lib/sysimage/libdnf5/transaction_history.sqlite*
