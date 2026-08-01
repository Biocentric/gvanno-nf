#!/usr/bin/env bash
#
# Build the entrezgene -> mim_phenotype_id map for the gene/transcript xref.
#
# Replaces OMIM's genemap2.txt, which is registration-gated. NCBI's
# mim2gene_medgen carries the same gene/phenotype MIM relationships and needs
# no account. It is also the more natural source here: the xref already stores
# UMLS CUIs and ClinVar speaks MedGen, so this keeps us in one namespace.
#
#   usage: extract-mim.sh [-i mim2gene_medgen] [-o out.tsv] [-u prior.tsv]
#
# -u unions in a prior map (same two-column format). NCBI covers 5126 genes vs
# the 20231224 bundle's 3853 — a net gain of 1418 — but it is not a superset:
# 145 genes drop out, and some retained genes lose individual associations
# (BRCA1 keeps 114480/604370/614320/617883 but loses 167000, ovarian cancer).
# Since the old bundle is already a build input, unioning is free and makes the
# result strictly >= what we ship today. Use it.
#
# Input  (NCBI, tab-separated, one header line beginning '#'):
#     #MIM number  GeneID  type  Source  MedGenCUI  Comment
#
# We keep rows with type == 'phenotype' AND a real GeneID; those are the
# gene->phenotype links. type == 'gene' rows carry the gene's OWN mim id, which
# is a different field (mim_id) and not what mim_phenotype_id holds.
#
# Output matches the upstream encoding: one row per gene, multiple phenotype
# MIMs joined with '&' in ascending order.
#     entrezgene  mim_phenotype_id
#     10002       268100&611131
#
set -uo pipefail

IN=/mnt/big/gvanno-refdata/mim2gene_medgen
OUT=mim_phenotype.tsv
UNION=

while getopts ":i:o:u:h" opt; do
    case $opt in
        i) IN=$OPTARG ;;
        o) OUT=$OPTARG ;;
        u) UNION=$OPTARG ;;
        h) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

[ -f "$IN" ] || { echo "missing input: $IN (run fetch-sources.sh -s ncbi_mim2gene)" >&2; exit 1; }
[ -n "$UNION" ] && [ ! -f "$UNION" ] && { echo "missing union input: $UNION" >&2; exit 1; }

# The union file is fed through the same pipeline by re-emitting it as
# NCBI-shaped rows (mim, gene, 'phenotype'), so dedup and sorting are shared.
{
    cat "$IN"
    [ -n "$UNION" ] && awk -F'\t' '{n=split($2,a,"&"); for(i=1;i<=n;i++) if(a[i]!="") print a[i]"\t"$1"\tphenotype\t-\t-\t-"}' "$UNION"
} | awk -F'\t' '
    /^#/    { next }
    $3 != "phenotype"          { next }
    $2 == "-" || $2 == ""      { next }
    {
        gene = $2; mim = $1
        # Dedupe via a separate key set. Testing membership by reading
        # seen[gene] would instantiate it as empty and prepend a stray "&".
        if ((gene SUBSEP mim) in pair) next
        pair[gene SUBSEP mim] = 1
        if (gene in seen) seen[gene] = seen[gene] "&" mim
        else              seen[gene] = mim
    }
    END {
        for (g in seen) {
            # sort the MIMs numerically so output is stable across runs
            n = split(seen[g], a, "&")
            for (i = 2; i <= n; i++) {
                v = a[i]; j = i - 1
                while (j > 0 && a[j] + 0 > v + 0) { a[j+1] = a[j]; j-- }
                a[j+1] = v
            }
            s = a[1]; for (i = 2; i <= n; i++) s = s "&" a[i]
            print g "\t" s
        }
    }
' | sort -k1,1n > "$OUT"

printf 'wrote %s\n' "$OUT"
printf '  genes with >=1 phenotype MIM : %s\n' "$(wc -l < "$OUT")"
printf '  total gene-phenotype links   : %s\n' \
       "$(awk -F'\t' '{n=split($2,a,"&"); t+=n} END{print t+0}' "$OUT")"
printf '  sample:\n'
head -3 "$OUT" | sed 's/^/    /'
