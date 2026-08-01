#!/usr/bin/env bash
#
# Package a built bundle: sha256 manifest, tarball, tarball checksum.
#
#   usage: package-bundle.sh [-a ASSEMBLY] [-v VERSION] [-b BUNDLEDIR] [-o OUTDIR]
#
# The manifest is plain `sha256sum` output with paths relative to the bundle
# root, which is exactly what BUNDLE_VERIFY feeds to `sha256sum -c` after
# cd-ing into --refdata_dir. Copy it to assets/refdata_manifest.<version>.tsv.
#
# .vep/ is excluded from BOTH the manifest and the tarball: the VEP cache is
# fetched separately from Ensembl and is not bundle content. Including it in
# the manifest would make verification fail on any bundle whose cache has not
# been staged yet.
#
# Note the 20231224 manifest shipped EMPTY, so BUNDLE_VERIFY has been silently
# skipping checksums since day one. This is the fix — verify the output is
# non-empty before shipping.
#
set -uo pipefail

ASM=grch38
VERSION=20260801
BUNDLE=/mnt/big/gvanno-build/bundle
OUT=/mnt/big/gvanno-build/dist

while getopts ":a:v:b:o:h" opt; do
    case $opt in
        a) ASM=$OPTARG ;; v) VERSION=$OPTARG ;;
        b) BUNDLE=$OPTARG ;; o) OUT=$OPTARG ;;
        h) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

log() { printf '[package] %s\n' "$*"; }
die() { printf '[package] ERROR: %s\n' "$*" >&2; exit 1; }

D=$BUNDLE/data/$ASM
[ -d "$D" ] || die "no bundle at $D"
grep -q "GVANNO_DB_VERSION = $VERSION" "$D/RELEASE_NOTES" 2>/dev/null \
    || die "RELEASE_NOTES does not declare version $VERSION"
mkdir -p "$OUT"

MANIFEST=$OUT/refdata_manifest.$VERSION.$ASM.tsv
TARBALL=$OUT/gvanno.databundle.$ASM.$VERSION.tgz

# --- manifest -------------------------------------------------------------
log "hashing bundle contents (excluding .vep/)"
( cd "$BUNDLE" && find "data/$ASM" -type f -not -path "*/.vep/*" -not -name '._*' \
    | LC_ALL=C sort | xargs -d '\n' sha256sum ) > "$MANIFEST" || die "hashing failed"

N=$(wc -l < "$MANIFEST")
[ "$N" -gt 0 ] || die "manifest is empty — this is the bug the 20231224 bundle shipped with"
log "manifest: $N entries -> $(basename "$MANIFEST")"

log "self-check (sha256sum -c, exactly as BUNDLE_VERIFY runs it)"
( cd "$BUNDLE" && sha256sum -c "$MANIFEST" --quiet ) || die "manifest self-check FAILED"
log "  all $N files verify"

# --- tarball --------------------------------------------------------------
log "creating tarball (this takes a few minutes)"
tar --exclude='.vep' --exclude='._*' -czf "$TARBALL" -C "$BUNDLE" "data/$ASM" \
    || die "tar failed"

SZ=$(du -h "$TARBALL" | cut -f1)
log "tarball: $SZ -> $(basename "$TARBALL")"

log "checksumming tarball"
( cd "$OUT" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256" )
log "  $(cat "$TARBALL.sha256")"

# --- GitHub Releases cap --------------------------------------------------
BYTES=$(stat -c %s "$TARBALL")
if [ "$BYTES" -gt 2000000000 ]; then
    log "NOTE: $((BYTES/1000000)) MB exceeds GitHub's 2 GB per-asset cap."
    log "      scripts/publish-refdata-mirror.sh splits it and writes a .parts.txt"
    log "      manifest, which BUNDLE_FETCH already knows how to reassemble."
fi

log "done"
ls -la "$OUT" | awk 'NR>1 && $5>0 {printf "  %9.2f MB  %s\n", $5/1048576, $9}'
