#!/usr/bin/env bash
#
# Build the Track B container.
#
#   bash container/build.sh            build only
#   bash container/build.sh --push     build and push to GHCR
#
# The image bakes in the gvanno helpers, fetched pinned from GitHub and patched
# at build time — they are not vendored here, because sigven/gvanno carries no
# licence. See README.md.
#
set -uo pipefail

IMAGE=${IMAGE:-ghcr.io/biocentric/gvanno-nf}
TAG=${TAG:-2026.1}
PUSH=0
[ "${1:-}" = "--push" ] && PUSH=1

cd "$(dirname "$0")" || exit 1

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
[ -d patches ] || { echo "no patches/ directory" >&2; exit 1; }
echo "[build] $(ls patches/*.patch | wc -l) patches to apply"

echo "[build] $IMAGE:$TAG"
docker build --pull -t "$IMAGE:$TAG" . || { echo "[build] FAILED" >&2; exit 1; }

echo
echo "[verify] runtime smoke check"
docker run --rm --entrypoint /bin/bash "$IMAGE:$TAG" -c '
  set -e
  printf "  vep        %s\n" "$(vep --help 2>/dev/null | grep -oP "ensembl-vep\s+:\s*\K[\d.]+" | head -1)"
  printf "  python3    %s\n" "$(python3 --version 2>&1 | cut -d" " -f2)"
  printf "  pandas     %s\n" "$(python3 -c "import pandas;print(pandas.__version__)")"
  printf "  samtools   %s\n" "$(samtools --version 2>/dev/null | head -1 | cut -d" " -f2)"
  printf "  bcftools   %s\n" "$(bcftools --version 2>/dev/null | head -1 | cut -d" " -f2)"
  printf "  vcfanno    %s\n" "$(vcfanno 2>&1 | head -1 | awk "{print \$2}")"
  printf "  LoF.pm     %s\n" "$(test -f /opt/vep/src/ensembl-vep/modules/LoF.pm && echo present || echo MISSING)"
  printf "  NearestExonJB.pm %s\n" "$(test -f /opt/vep/src/ensembl-vep/modules/NearestExonJB.pm && echo present || echo MISSING)"
  python3 -c "import sys;sys.path.insert(0,\"/gvanno/lib\");from gvanno import gvanno_vars as v;print(\"  VEP_VERSION\",v.VEP_VERSION,\"GENCODE\",v.GENCODE_VERSION)"
' || { echo "[verify] FAILED" >&2; exit 1; }

if [ "$PUSH" = "1" ]; then
    echo
    echo "[push] $IMAGE:$TAG"
    # GHCR needs a token with write:packages — the repo token has repo scope only.
    docker push "$IMAGE:$TAG" || {
        echo "[push] FAILED. Authenticate first:" >&2
        echo "  echo \$GHCR_TOKEN | docker login ghcr.io -u Biocentric --password-stdin" >&2
        echo "The token needs write:packages, which the existing repo-scoped token lacks." >&2
        exit 1; }
    echo "[push] done"
fi

echo "[build] complete: $IMAGE:$TAG"
