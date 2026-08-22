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
# we end up shipping.
dnf install -y --setopt=tsflags=noscripts \
    akmods \
    kmodtool \
    gcc \
    make \
    nct6687d

KERNEL="$(ls -1 /usr/lib/modules | sort -V | tail -1)"

# The upgrade leaves the previous kernel behind; purge it so the image ships
# exactly one kernel (the one we build the module for)
KVR="${KERNEL%.*}"
OLD_KERNEL_PKGS="$(rpm -qa kernel kernel-core kernel-modules kernel-modules-extra kernel-modules-core kernel-devel --qf '%{NAME}-%{EVR}.%{ARCH}\n' | grep -v -- "-${KVR}." | sort -u || true)"
if [[ -n "${OLD_KERNEL_PKGS}" ]]; then
  dnf remove -y ${OLD_KERNEL_PKGS}
fi

akmods --force --kernels "${KERNEL}"

dnf remove -y kernel-devel-${KERNEL} gcc make
dnf clean all

sed -i 's/Kinoite/BrOS/g' /usr/lib/os-release

### Remove build-state files that would otherwise differ on every build
# and invalidate the layers containing them
rm -fv /var/lib/dnf/repos/*/countme
rm -fv /usr/lib/sysimage/libdnf5/transaction_history.sqlite*
