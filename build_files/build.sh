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
    docker-compose \
    krb5-workstation \
    kvantum \
    virt-manager \
    wireshark \
    zsh \
    strace \
    ncdu \
    rsms-inter-fonts \
    tailscale

### Tailscale

# tailscale comes from Tailscale's own Fedora repo, not the Fedora
# repos. The repo definition is vendored in
# system_files/etc/yum.repos.d/tailscale.repo (verbatim from
# https://pkgs.tailscale.com/stable/fedora/tailscale.repo, same
# pattern as vscode.repo) and was copied to / at the top of this
# script, before the dnf install above. Its baseurl is
# Fedora-version-agnostic ($basearch only, no $releasever), so the
# same repo works on both the 44 and 45 build legs.
# The vendored file is used instead of dnf config-manager
# --add-repo: that is dnf4 syntax and is an unknown argument on
# the dnf5 shipped by Fedora 44/45.
# The daemon is deliberately NOT enabled in the image: enabling
# it and joining a tailnet are per-machine steps, done on the
# installed system (`systemctl enable --now tailscaled`, then
# `sudo tailscale up`).

### Inter font

# rsms-inter-fonts is Fedora's package of the Inter UI font. It was
# previously installed only per-user on moshke, in
# ~/.local/share/fonts/inter (Version 3.015), while the KDE and GTK
# configuration already names Inter as the UI font -- so a fresh
# install without that per-user copy would silently fall back.
# The Fedora package is 4.1 on both build legs (4.1-3.fc44 and
# 4.1-4.fc45), the non-variable static OTFs, installed to
# /usr/share/fonts/rsms-inter-fonts/. Installing it here is a
# deliberate version jump from the local 3.015 copy.
# No default is set in the image: fontconfig and desktop defaults
# are unchanged, and which font the UI uses remains a per-user
# setting. This only makes the family available system-wide.

### Fedora 45: OpenSSL 3 compat library for VS Code extension installs

# Fedora 45 moved the system OpenSSL to 4.x; libssl.so.3 moved to the
# separate openssl3-libs compat package, which nothing pulls in.
# VS Code verifies marketplace extensions with its bundled .NET helper
# vsce-sign, which only probes for libssl.so.3 (or older) and aborts
# without it, so every extension install fails with a signature
# verification UnknownError while the editor itself works fine.
# Guarded by Fedora version: on 44 libssl.so.3 is the system library
# (openssl-libs) and openssl3-libs does not exist.
if [[ "$(rpm -E %fedora)" -ge 45 ]]; then
  dnf install -y openssl3-libs
fi

### Remove packages we don't want from the base image

# The base image ships the RPM Firefox (and its langpacks); we use the
# Flatpak instead. Guarded so the build doesn't break if a future base
# image stops shipping it.
FIREFOX_PKGS="$(rpm -qa 'firefox*' --qf '%{NAME}\n' | sort -u || true)"
if [[ -n "${FIREFOX_PKGS}" ]]; then
  dnf remove -y ${FIREFOX_PKGS}
fi

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
