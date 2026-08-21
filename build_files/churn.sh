#!/bin/bash

# Moves known-volatile files into a dedicated image layer:
#
# - rpmdb / dnf transaction history / countme: rewritten by every dnf run
#   with fresh timestamps
# - the out-of-tree nct6687d kmod: akmods rebuilds it on every run; even
#   with identical source the binary differs (fresh GNU build-id), and
#   kernel/gcc updates would change bytes anyway
#
# Container layers are filesystem diffs: whatever bytes a RUN step writes
# land in that step's layer. Without special handling these files make
# every rebuild produce new layers even when nothing else changed.
#
# The trick:
#   churn.sh snapshot - remember the pristine copies before any dnf work
#   churn.sh stash    - stage post-build copies in $STASH_DIR and rewind
#                       the canonical paths to their pristine state, so
#                       they produce no diff for the main build layer
#   churn.sh reveal   - place the staged copies back; run as its own tiny
#                       RUN step so only this layer carries the churn
#
# $STASH_DIR is expected to be a --mount=type=cache destination, which is
# never committed to any image layer. $CHURN_ROOT defaults to / and only
# exists so the logic can be exercised outside of a container build.

set -euox pipefail

STASH_DIR="${CHURN_STASH:-/churn}"
PRISTINE_DIR="${STASH_DIR}/pristine"
FINAL_DIR="${STASH_DIR}/final"
ROOT="${CHURN_ROOT:-/}"

GLOBS=(
    "usr/share/rpm/rpmdb.sqlite*"
    "usr/lib/sysimage/libdnf5/transaction_history.sqlite*"
    "var/lib/dnf/repos/*/countme"
    "usr/lib/modules/*/extra/nct6687d"
)

matches() {
    local g
    for g in "${GLOBS[@]}"; do
        compgen -G "${ROOT}/${g}" || true
    done
}

snapshot() {
    rm -rf "${PRISTINE_DIR}"
    mkdir -p "${PRISTINE_DIR}"
    local f dst
    while IFS= read -r f; do
        dst="${PRISTINE_DIR}${f#"${ROOT}"}"
        mkdir -p "$(dirname "${dst}")"
        cp -a "$f" "${dst}"
    done < <(matches)
}

stash() {
    if [[ ! -d "${PRISTINE_DIR}" ]]; then
        echo "error: run 'churn.sh snapshot' before any dnf work" >&2
        exit 1
    fi
    # Drop leftovers from earlier builds so reveal never resurrects them
    rm -rf "${FINAL_DIR}" "${STASH_DIR}/manifest"
    mkdir -p "${FINAL_DIR}"
    local f rel
    while IFS= read -r f; do
        rel="${f#"${ROOT}"}"
        mkdir -p "$(dirname "${FINAL_DIR}${rel}")"
        cp -a "$f" "${FINAL_DIR}${rel}"
        printf '%s\n' "$rel" >> "${STASH_DIR}/manifest"
        # Rewind to pristine; cp would nest into an existing directory,
        # so clear the path first
        rm -rf "$f"
        if [[ -e "${PRISTINE_DIR}${rel}" ]]; then
            cp -a "${PRISTINE_DIR}${rel}" "$f"
        else
            # Drop now-empty parents the base image didn't have, so no
            # trace of this build remains outside the churn layer
            local d="$(dirname "$f")"
            while [[ "$d" != "${ROOT}" && ! -e "${PRISTINE_DIR}${d#"${ROOT}"}" ]]; do
                rmdir "$d" 2>/dev/null || break
                d="$(dirname "$d")"
            done
        fi
    done < <(matches)
}

reveal() {
    if [[ ! -s "${STASH_DIR}/manifest" ]]; then
        echo "error: nothing staged under ${FINAL_DIR}; refusing to ship an image without its rpmdb" >&2
        exit 1
    fi
    local n=0 rel dest
    while IFS= read -r rel; do
        dest="${ROOT}${rel}"
        # Clear the destination first; mv would otherwise nest a staged
        # directory inside an existing one
        rm -rf "${dest}"
        mkdir -p "$(dirname "${dest}")"
        mv "${FINAL_DIR}${rel}" "${dest}"
        n=$((n + 1))
    done < "${STASH_DIR}/manifest"
    if [[ "$n" -eq 0 ]]; then
        echo "error: staged no volatile files; refusing to continue" >&2
        exit 1
    fi
    echo "revealed ${n} volatile path(s) into this layer"
}

case "${1:-}" in
snapshot | stash | reveal)
    "$1"
    ;;
*)
    echo "usage: $0 {snapshot|stash|reveal}" >&2
    exit 2
    ;;
esac
