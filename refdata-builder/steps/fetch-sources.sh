#!/usr/bin/env bash
#
# Fetch every source needed to build a gvanno reference bundle.
#
# All sources are account-free by design — the builder must run unattended with
# no stored credentials. See config/sources.yml for what replaces the
# registration-gated upstreams (COSMIC Cancer Gene Census, OMIM genemap2).
#
#   usage: fetch-sources.sh [-d DESTDIR] [-a ASSEMBLY] [-s SOURCE]...
#
#     -d  destination           (default: /mnt/big/gvanno-refdata)
#     -a  assembly              grch38 | grch37 | both   (default: grch38)
#     -s  fetch only this source; repeatable. One of:
#           gvanno_current pcgr_2026 pcgr_2025 ncbi_mim2gene hgnc
#
# Idempotent and resumable: existing complete files are left alone, partial
# downloads resume via curl -C -. Bundles with a known sha256 are verified and
# re-fetched once on mismatch.
#
set -uo pipefail

DEST=/mnt/big/gvanno-refdata
ASSEMBLIES=(grch38)
ONLY=()

while getopts ":d:a:s:h" opt; do
    case $opt in
        d) DEST=$OPTARG ;;
        a) if [ "$OPTARG" = both ]; then ASSEMBLIES=(grch38 grch37); else ASSEMBLIES=("$OPTARG"); fi ;;
        s) ONLY+=("$OPTARG") ;;
        h) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

mkdir -p "$DEST" || exit 1
cd "$DEST" || exit 1

wanted() {
    [ ${#ONLY[@]} -eq 0 ] && return 0
    local s
    for s in "${ONLY[@]}"; do [ "$s" = "$1" ] && return 0; done
    return 1
}

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# fetch <url> <outfile> [expected_sha256]
fetch() {
    local url=$1 out=$2 want=${3:-}

    if [ -f "$out" ] && [ -n "$want" ]; then
        local have
        have=$(sha256sum "$out" | cut -d' ' -f1)
        if [ "$have" = "$want" ]; then log "have    $out (sha256 ok)"; return 0; fi
        log "WARN    $out failed checksum — refetching"
        mv -f "$out" "$out.bad"
    elif [ -f "$out" ]; then
        log "have    $out (no checksum on record)"; return 0
    fi

    log "fetch   $out"
    if ! curl -fL -C - --retry 5 --retry-delay 10 --retry-all-errors \
              --progress-bar -o "$out" "$url"; then
        log "ERROR   failed: $url"; return 1
    fi

    if [ -n "$want" ]; then
        local have
        have=$(sha256sum "$out" | cut -d' ' -f1)
        if [ "$have" != "$want" ]; then
            log "ERROR   checksum mismatch for $out"
            log "        expected $want"
            log "        got      $have"
            return 1
        fi
        log "ok      $out (sha256 verified)"
    else
        log "ok      $out ($(du -h "$out" | cut -f1))"
    fi
}

# --- sha256 of the pinned donor bundles (see config/sources.yml) ------------
sha_gvanno_grch38=35665b6ee6120647d0fd6e45258a90e4a5ecc019df03a08992c7ce8a698e6eea
sha_gvanno_grch37=fcca0ebfdd2c2629bbb721fe09c169b7471343a7392382bc37a2f63bec423034
sha_pcgr26_grch38=f9b8149e37c7e63bd7d877713cdb11a1a609c492b3f1a055fb7e90cd80273e54
sha_pcgr26_grch37=03f872138dfb3e533d56f16fc7587b8543a3dfd605b39c7b9d4a7f9a4768fa5c

rc=0
OSLO=https://insilico.hpc.uio.no/pcgr

for asm in "${ASSEMBLIES[@]}"; do
    log "=== assembly: $asm ==="

    # 1. the bundle being replaced — format spec + ncER carry-forward, and the
    #    fallback source for CGC/MIM if the steps below ever go dark
    if wanted gvanno_current; then
        eval "want=\$sha_gvanno_$asm"
        fetch "$OSLO/gvanno/gvanno.databundle.$asm.20231224.tgz" \
              "gvanno.databundle.$asm.20231224.tgz" "$want" || rc=1
    fi

    # 2. primary donor — ClinVar 2026-06, dbNSFP v5.3, hotspots v3, GENCODE v49
    if wanted pcgr_2026; then
        eval "want=\$sha_pcgr26_$asm"
        fetch "$OSLO/pcgr_ref_data.20260620.$asm.tgz" \
              "pcgr_ref_data.20260620.$asm.tgz" "$want" || rc=1
    fi

    # 3. CGC donor — PCGR 2.3 dropped cgc_*; the 2.2-era bundle still has it
    #    (Cancer Gene Census v101, 2025). Avoids needing a COSMIC account.
    if wanted pcgr_2025; then
        fetch "$OSLO/pcgr_ref_data.20250314.$asm.tgz" \
              "pcgr_ref_data.20250314.$asm.tgz" || rc=1
    fi
done

# --- assembly-independent open sources -------------------------------------

# 4. MIM phenotype <-> gene. Replaces OMIM genemap2.txt (registration-gated).
if wanted ncbi_mim2gene; then
    log "=== NCBI mim2gene_medgen ==="
    fetch "https://ftp.ncbi.nlm.nih.gov/gene/DATA/mim2gene_medgen" mim2gene_medgen || rc=1
    [ -f mim2gene_medgen ] && log "        $(wc -l < mim2gene_medgen) rows"
fi

# 5. HGNC complete set — symbol authority + omim_id cross-check.
#    NB: the old EBI path 404s; this Google mirror is the live one.
if wanted hgnc; then
    log "=== HGNC complete set ==="
    fetch "https://storage.googleapis.com/public-download-files/hgnc/tsv/tsv/hgnc_complete_set.txt" \
          hgnc_complete_set.txt || rc=1
    [ -f hgnc_complete_set.txt ] && log "        $(wc -l < hgnc_complete_set.txt) rows"
fi

log "=== summary ==="
ls -la "$DEST" 2>/dev/null | awk 'NR>1 && $5>0 {printf "  %10.2f MB  %s\n", $5/1048576, $9}'
[ $rc -eq 0 ] && log "all sources present" || log "FINISHED WITH ERRORS"
exit $rc
