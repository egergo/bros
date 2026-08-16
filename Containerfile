FROM quay.io/fedora-ostree-desktops/kinoite:44

# COPY copr-egergo-mine.repo /etc/yum.repos.d/copr-egergo-mine.repo
COPY vscode.repo /etc/yum.repos.d/vscode.repo

RUN dnf install -y dnf-plugins-core \
 && dnf copr enable -y egergo/mine \
 && KERNEL="$(ls /usr/lib/modules)" \
 && dnf install -y --setopt=tsflags=nodocs \
        code \
        distrobox \
        krb5-workstation \
        kvantum \
        virt-manager \
        wireshark \
        zsh \
        strace \
        ncdu \
 && dnf install -y --setopt=tsflags=noscripts \
        akmods \
        kmodtool \
        gcc \
        make \
        kernel-devel-${KERNEL} \
        nct6687d \
 && akmods --force --kernels "${KERNEL}" \
 && dnf remove -y kernel-devel-${KERNEL} gcc make \
 && dnf clean all
