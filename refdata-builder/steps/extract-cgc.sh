#!/usr/bin/env bash
#
# Build the Cancer Gene Census map for the gene/transcript xref.
#
# Replaces a COSMIC account. PCGR 2.3 (bundle 20260620) DROPPED cgc_tier,
# cgc_somatic and cgc_germline from its gene xref; the 2.2-era bundle
# (20250314) still carries them, sourced from Cancer Gene Census v101 (2025).
# Both bundles are on the same open Oslo host we already fetch from.
#
#   usage: extract-cgc.sh [-b BUNDLE_TGZ_OR_DIR] [-o out.tsv] [-w workdir]
#
# Output, one row per gene:
#     ensembl_gene_id  entrezgene  symbol  cgc_tier  cgc_somatic  cgc_germline
#
set -uo pipefail

SRC=/mnt/big/gvanno-refdata/pcgr_ref_data.20250314.grch38.tgz
OUT=cgc.tsv
WORK=/mnt/big/gvanno-build/pcgr-20250314

while getopts ":b:o:w:h" opt; do
    case $opt in
        b) SRC=$OPTARG ;;
        o) OUT=$OPTARG ;;
        w) WORK=$OPTARG ;;
        h) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

# Accept either the tarball (extract just the gene subtree — the rest is 4+ GB
# we do not need) or an already-extracted directory.
if [ -f "$SRC" ]; then
    mkdir -p "$WORK"
    if ! find "$WORK" -name 'gene_transcript_xref.tsv.gz' -print -quit | grep -q .; then
        echo "[cgc] extracting gene/ subtree from $(basename "$SRC")"
        tar -xzf "$SRC" -C "$WORK" --wildcards '*/gene/*' '*/.PCGR_BUNDLE_VERSION' 2>/dev/null
    fi
    ROOT=$WORK
elif [ -d "$SRC" ]; then
    ROOT=$SRC
else
    echo "not found: $SRC (run fetch-sources.sh -s pcgr_2025)" >&2; exit 1
fi

X=$(find "$ROOT" -name 'gene_transcript_xref.tsv.gz' | head -1)
[ -n "$X" ] || { echo "no gene_transcript_xref.tsv.gz under $ROOT" >&2; exit 1; }
echo "[cgc] source: $X  (bundle $(find "$ROOT" -name '.PCGR_BUNDLE_VERSION' -exec cat {} \; 2>/dev/null | head -1))"

# Resolve columns by NAME, never by position — PCGR reorders between releases.
zcat "$X" | awk -F'\t' '
    NR == 1 {
        for (i = 1; i <= NF; i++) c[$i] = i
        for (k in c) ;
        req = "ensembl_gene_id entrezgene symbol cgc_tier cgc_somatic cgc_germline"
        n = split(req, r, " ")
        for (i = 1; i <= n; i++)
            if (!(r[i] in c)) { printf "missing column: %s\n", r[i] > "/dev/stderr"; bad = 1 }
        if (bad) exit 3
        print "ensembl_gene_id\tentrezgene\tsymbol\tcgc_tier\tcgc_somatic\tcgc_germline"
        next
    }
    {
        g = $c["ensembl_gene_id"]
        if (g == "" || g == "NA" || g == ".") next
        # keep only genes with an actual census record
        t = $c["cgc_tier"]
        if (t == "" || t == "NA" || t == ".") next
        if (g in seen) next
        seen[g] = 1
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", g, $c["entrezgene"], $c["symbol"],
               t, $c["cgc_somatic"], $c["cgc_germline"]
    }
' > "$OUT" || { echo "[cgc] FAILED — column layout changed?" >&2; exit 3; }

printf 'wrote %s\n' "$OUT"
printf '  census genes           : %s\n' "$(( $(wc -l < "$OUT") - 1 ))"
printf '  distinct cgc_tier      : %s\n' \
       "$(awk -F'\t' 'NR>1{print $4}' "$OUT" | sort -u | tr '\n' ' ')"
printf '  distinct cgc_somatic   : %s\n' \
       "$(awk -F'\t' 'NR>1{print $5}' "$OUT" | sort -u | tr '\n' ' ')"
printf '  distinct cgc_germline  : %s\n' \
       "$(awk -F'\t' 'NR>1{print $6}' "$OUT" | sort -u | tr '\n' ' ')"
printf '  sample:\n'
head -4 "$OUT" | sed 's/^/    /'
