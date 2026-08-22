#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

dnf install -y dnf-plugins-core

dnf copr enable -y egergo/mine

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

if ! rpm -q kernel-devel-${KERNEL} &>/dev/null; then
  KD_ARCH="${KERNEL##*.}"           # x86_64
  KD_REL="${KERNEL#*-}"             # 200.fc44.x86_64
  KD_REL="${KD_REL%."${KD_ARCH}"}"  # 200.fc44
  KD_VER="${KERNEL%%-*}"

  dnf install -y --setopt=tsflags=noscripts "kernel-devel-${KERNEL}" || \
    dnf install -y --setopt=tsflags=noscripts \
      "https://kojipkgs.fedoraproject.org/packages/kernel/${KD_VER}/${KD_REL}/${KD_ARCH}/kernel-devel-${KERNEL}.rpm"
fi

akmods --force --kernels "${KERNEL}"

if rpm -q kernel-devel-${KERNEL} &>/dev/null; then
  dnf remove -y kernel-devel-${KERNEL} gcc make
fi
dnf clean all

sed -i 's/Kinoite/BrOS/g' /usr/lib/os-release

### Remove build-state files that would otherwise differ on every build
# and invalidate the layers containing them
rm -fv /var/lib/dnf/repos/*/countme
rm -fv /usr/lib/sysimage/libdnf5/transaction_history.sqlite*
