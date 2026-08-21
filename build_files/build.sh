#!/bin/bash

set -ouex pipefail

# Reference point for churn.sh normalize: everything written after this
# moment gets its mtime pinned before the layer is committed, so an
# unchanged tree yields a byte-identical layer
export CHURN_SINCE="$(date +%s)"

# Remember the pristine bookkeeping files before any dnf work touches them
/ctx/churn.sh snapshot

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /
# cp preserves their checkout-time mtimes, which differ on every runner;
# pin them along with everything else this run writes
while IFS= read -r -d '' src; do
    touch -h -d @0 -- "${src#/ctx/system_files}"
done < <(find /ctx/system_files -mindepth 1 -print0)

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

# Pin mtimes of everything the run touched (mime db, selinux policy,
# depmod indexes, ld.so.cache, ...), then stage the churned bookkeeping
# files and rewind them to their pristine state; the reveal step puts
# them back in a dedicated final layer
/ctx/churn.sh normalize
/ctx/churn.sh stash
