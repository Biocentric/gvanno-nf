#!/usr/bin/env bash
# ----------------------------------------------------------------------------
#  publish-refdata-mirror.sh
#
#  One-shot script that mirrors the upstream gvanno refdata bundle onto this
#  repository's GitHub Releases page, splitting the bundle into ≤ 2 GB chunks
#  (GitHub's per-asset cap) and uploading a `*.parts.txt` manifest alongside.
#
#  BUNDLE_FETCH on the pipeline side already knows how to consume this layout:
#  it tries the direct URL first, and on 404 falls back to the manifest +
#  chunk reassembly path. So once this script has run successfully, the
#  pipeline's `--refdata_mode download` works against the GH mirror with no
#  further code changes.
#
#  Run this:
#    - on a host with `gh`, `curl`, `split`, `sha256sum` installed
#    - while authenticated against github.com/Biocentric (`gh auth status`)
#    - with at least ~10 GB free disk
#
#  Usage:
#    bash scripts/publish-refdata-mirror.sh                # all assemblies
#    bash scripts/publish-refdata-mirror.sh grch37         # one assembly
#    REFDATA_VERSION=20231224 bash scripts/publish-refdata-mirror.sh
#
#  Idempotent: skips assets that already exist on the release.
# ----------------------------------------------------------------------------
set -euo pipefail

REFDATA_VERSION="${REFDATA_VERSION:-20231224}"
REPO="${REPO:-Biocentric/gvanno-nf}"
TAG="refdata-${REFDATA_VERSION}"
UPSTREAM="${UPSTREAM:-http://insilico.hpc.uio.no/pcgr/gvanno}"
WORKDIR="${WORKDIR:-./.refdata-mirror}"
CHUNK_SIZE="${CHUNK_SIZE:-1900M}"

ASSEMBLIES=("${@:-grch37 grch38}")

echo "[publish] repo:    ${REPO}"
echo "[publish] tag:     ${TAG}"
echo "[publish] workdir: ${WORKDIR}"
echo "[publish] chunk:   ${CHUNK_SIZE}"
echo "[publish] genomes: ${ASSEMBLIES[*]}"

mkdir -p "${WORKDIR}"

# ----------------------------------------------------------------------------
# 0. preflight
# ----------------------------------------------------------------------------
for cmd in gh curl split sha256sum; do
    command -v "${cmd}" >/dev/null || { echo "[publish] missing: ${cmd}"; exit 1; }
done

if ! gh auth status >/dev/null 2>&1; then
    echo "[publish] gh not authenticated. Run: gh auth login"
    exit 1
fi

# ----------------------------------------------------------------------------
# 1. ensure release exists
# ----------------------------------------------------------------------------
if ! gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    echo "[publish] creating release ${TAG}"
    gh release create "${TAG}" \
        --repo "${REPO}" \
        --title "refdata bundle ${REFDATA_VERSION} (mirror of upstream gvanno)" \
        --notes "Mirror of the gvanno reference bundle ${REFDATA_VERSION} as published by Sigve Nakken at https://github.com/sigven/gvanno. Hosted here so \`Biocentric/gvanno-nf\` has a redundant download path that does not depend on the upstream Oslo mirror staying online. Each assembly's bundle is split into ${CHUNK_SIZE} chunks; \`*.parts.txt\` is the manifest of chunk filenames. The pipeline's BUNDLE_FETCH module reassembles chunks transparently." \
        --prerelease=false
fi

upload() {
    local f="$1"
    local name; name=$(basename "${f}")
    if gh release view "${TAG}" --repo "${REPO}" --json assets --jq '.assets[].name' | grep -qx "${name}"; then
        echo "[publish]   already uploaded: ${name}"
    else
        echo "[publish]   uploading: ${name} ($(du -h "${f}" | cut -f1))"
        gh release upload "${TAG}" "${f}" --repo "${REPO}" --clobber
    fi
}

mirror_one() {
    local assembly="$1"
    local bundle="gvanno.databundle.${assembly}.${REFDATA_VERSION}.tgz"
    local local_path="${WORKDIR}/${bundle}"

    echo
    echo "=== ${assembly} ==="

    # 2. download bundle from upstream if not cached
    if [ ! -f "${local_path}" ]; then
        echo "[publish] downloading ${UPSTREAM}/${bundle}"
        curl -fSL --retry 5 -o "${local_path}" "${UPSTREAM}/${bundle}"
    else
        echo "[publish] cached: ${local_path}"
    fi

    # 3. split into chunks
    local parts_dir="${WORKDIR}/parts-${assembly}"
    mkdir -p "${parts_dir}"
    if [ -z "$(ls -A "${parts_dir}" 2>/dev/null)" ]; then
        echo "[publish] splitting into ${CHUNK_SIZE} chunks"
        ( cd "${parts_dir}" && split -b "${CHUNK_SIZE}" -d -a 2 "${local_path}" "${bundle}.part-" )
    fi

    # 4. write manifest
    local manifest="${parts_dir}/${bundle}.parts.txt"
    ( cd "${parts_dir}" && ls "${bundle}.part-"* | sort ) > "${manifest}"
    echo "[publish] manifest:"
    sed 's/^/    /' "${manifest}"

    # 5. write sha256 sidecar (consumed by BUNDLE_VERIFY in a future revision)
    ( cd "${parts_dir}" && sha256sum "${bundle}.part-"* "$(basename ${manifest})" ) > "${parts_dir}/${bundle}.sha256"

    # 6. upload everything
    for f in "${manifest}" "${parts_dir}/${bundle}.sha256" "${parts_dir}/${bundle}.part-"*; do
        upload "${f}"
    done

    echo "[publish] ${assembly} done"
}

for asm in "${ASSEMBLIES[@]}"; do
    mirror_one "${asm}"
done

echo
echo "[publish] all done. Release URL:"
gh release view "${TAG}" --repo "${REPO}" --json url --jq '.url'
