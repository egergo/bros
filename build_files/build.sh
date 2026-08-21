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

dnf install -y --setopt=tsflags=noscripts \
    akmods \
    kmodtool \
    gcc \
    make \
    kernel-devel-${KERNEL} \
    nct6687d

akmods --force --kernels "${KERNEL}"

dnf remove -y kernel-devel-${KERNEL} gcc make
dnf clean all

sed -i 's/Kinoite/BrOS/g' /usr/lib/os-release
