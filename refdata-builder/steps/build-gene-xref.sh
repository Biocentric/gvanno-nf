#!/usr/bin/env bash
#
# Build the gene/transcript xref — the last piece of the bundle.
#
#   usage: build-gene-xref.sh [-a ASSEMBLY] [-o OUTDIR]
#
# PCGR 2.3 reordered the xref tag and dropped four fields gvanno needs, so this
# remaps its 33 fields into gvanno's 34-field order and injects the missing
# four from the account-free maps built by extract-cgc.sh / extract-mim.sh.
#
#   PCGR -> gvanno   drop cds_start, mane_select2, mane_plus_clinical2
#   inject           cgc_tier, cgc_somatic, cgc_germline   (by ensembl_gene_id)
#                    mim_phenotype_id                      (by entrezgene)
#
# Encoding note: PCGR stores the CGC flags as TRUE/FALSE, gvanno as 1/empty.
# Converted here, or every downstream TSG/oncogene flag would read as the
# string "FALSE" — which is truthy.
#
# Produces: gene_transcript_xref.bed.gz(+tbi), _pc_nopad.bed.gz(+tbi),
#           gene_transcript_xref.tsv.gz, gene_transcript_xref_bedmap.tsv.gz,
#           gene_transcript_xref.vcfanno.vcf_info_tags.txt
#
set -uo pipefail

ASM=grch38
OUT=/mnt/big/gvanno-build/bundle
BUILD=/mnt/big/gvanno-build
CONTAINER=sigven/gvanno:1.7.0

while getopts ":a:o:h" opt; do
    case $opt in
        a) ASM=$OPTARG ;;  o) OUT=$OPTARG ;;
        h) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

PCGR=$BUILD/pcgr-20260620/data/$ASM
OLD=$BUILD/ref-20231224/data/$ASM
D=$OUT/data/$ASM/gene
CGC=$BUILD/out/cgc.tsv
MIM=$BUILD/out/mim_phenotype.tsv

log() { printf '[xref] %s\n' "$*"; }
die() { printf '[xref] ERROR: %s\n' "$*" >&2; exit 1; }

for f in "$CGC" "$MIM"; do [ -f "$f" ] || die "missing $f (run: make cgc mim)"; done
mkdir -p "$D/bed/gene_transcript_xref" "$D/tsv/gene_transcript_xref"

# gvanno's 34 fields, in order. Single source of truth: drives the remap, the
# bedmap and the tag description below.
FIELDS="ENSEMBL_TRANSCRIPT_ID ENSEMBL_GENE_ID ENSEMBL_PROTEIN_ID SYMBOL ENTREZGENE
UNIPROT_ID UNIPROT_ACC REFSEQ_TRANSCRIPT_ID REFSEQ_PROTEIN_ID PRINCIPAL_ISOFORM_FLAG
GENCODE_TAG GENCODE_TRANSCRIPT_BIOTYPE ACTIONABLE_GENE TSG TSG_SUPPORT TSG_RANK
ONCOGENE ONCOGENE_SUPPORT ONCOGENE_RANK DRIVER DRIVER_SUPPORT CGC_TIER CGC_SOMATIC
CGC_GERMLINE INTOGEN_ROLE TCGA_DRIVER NCG_DRIVER CPG_SOURCE CPG_CANCER_CUI
CPG_SYNDROME_CUI CPG_MOI CPG_MOD GE_PANEL_ID MIM_PHENOTYPE_ID"

# --------------------------------------------------------------------------
# BED remap
# --------------------------------------------------------------------------
remap_bed() {   # remap_bed <in.bed.gz> <out.bed>
    zcat "$1" | awk -F'\t' -v cgc="$CGC" -v mim="$MIM" '
    BEGIN {
        # gvanno position -> PCGR position (0 = injected, not from PCGR)
        split("1 2 3 5 6 7 8 9 10 13 14 15 16 17 18 19 20 21 22 23 24 0 0 0 25 26 27 28 29 30 31 32 33 0", M, " ")
        while ((getline line < cgc) > 0) {
            n = split(line, c, "\t")
            if (c[1] == "ensembl_gene_id" || n < 6) continue
            tier[c[1]] = c[4]
            som[c[1]]  = (c[5] == "TRUE") ? "1" : ""
            germ[c[1]] = (c[6] == "TRUE") ? "1" : ""
        }
        while ((getline line < mim) > 0) {
            split(line, m, "\t"); phen[m[1]] = m[2]
        }
    }
    {
        np = split($4, p, "|")
        g = p[2]; e = p[6]                 # ensembl_gene_id, entrezgene
        out = ""
        for (i = 1; i <= 34; i++) {
            v = ""
            if      (i == 22) v = (g in tier) ? tier[g] : ""
            else if (i == 23) v = (g in som)  ? som[g]  : ""
            else if (i == 24) v = (g in germ) ? germ[g] : ""
            else if (i == 34) v = (e in phen) ? phen[e] : ""
            else if (M[i] > 0 && M[i] <= np) v = p[M[i]]
            out = out (i > 1 ? "|" : "") v
        }
        print $1 "\t" $2 "\t" $3 "\t" out
    }' > "$2"
}

log "remapping main BED (PCGR 33 fields -> gvanno 34)"
remap_bed "$PCGR/gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz" \
          "$BUILD/xref.bed" || die "remap failed"
log "remapping pc_nopad BED"
remap_bed "$PCGR/gene/bed/gene_transcript_xref/gene_transcript_xref_pc_nopad.bed.gz" \
          "$BUILD/xref_pc.bed" || die "remap failed"

log "sort + bgzip + tabix"
docker run --rm -v "$BUILD":/w --entrypoint /bin/bash "$CONTAINER" -c '
    set -e
    for f in xref xref_pc; do
        sort -k1,1 -k2,2n /w/$f.bed > /w/$f.sorted.bed
        bgzip -f -c /w/$f.sorted.bed > /w/$f.bed.gz
        tabix -f -p bed /w/$f.bed.gz
    done' || die "index failed"

B=$D/bed/gene_transcript_xref
mv -f "$BUILD/xref.bed.gz"        "$B/gene_transcript_xref.bed.gz"
mv -f "$BUILD/xref.bed.gz.tbi"    "$B/gene_transcript_xref.bed.gz.tbi"
mv -f "$BUILD/xref_pc.bed.gz"     "$B/gene_transcript_xref_pc_nopad.bed.gz"
mv -f "$BUILD/xref_pc.bed.gz.tbi" "$B/gene_transcript_xref_pc_nopad.bed.gz.tbi"
rm -f "$BUILD"/xref*.bed "$BUILD"/xref*.sorted.bed

# --------------------------------------------------------------------------
# wide TSV — project PCGR onto gvanno's column set, then override the four
# injected fields. gvanno_finalize.py reads this.
# --------------------------------------------------------------------------
log "projecting wide TSV onto the 20231224 column set"
zcat "$OLD/gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz" | head -1 > "$BUILD/xref_cols.txt"
zcat "$PCGR/gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz" \
  | awk -F'\t' -v want="$(cat "$BUILD/xref_cols.txt")" -v cgc="$CGC" -v mim="$MIM" '
    BEGIN {
        n = split(want, w, "\t")
        while ((getline line < cgc) > 0) { split(line, c, "\t")
            if (c[1] == "ensembl_gene_id") continue
            tier[c[1]] = c[4]
            som[c[1]]  = (c[5] == "TRUE") ? "1" : ""
            germ[c[1]] = (c[6] == "TRUE") ? "1" : "" }
        while ((getline line < mim) > 0) { split(line, m, "\t"); phen[m[1]] = m[2] }
    }
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; print want; next }
    {
        g = col["ensembl_gene_id"] ? $col["ensembl_gene_id"] : ""
        e = col["entrezgene"]      ? $col["entrezgene"]      : ""
        s = ""
        for (i = 1; i <= n; i++) {
            k = w[i]; v = ""
            if      (k == "cgc_tier")         v = (g in tier) ? tier[g] : ""
            else if (k == "cgc_somatic")      v = (g in som)  ? som[g]  : ""
            else if (k == "cgc_germline")     v = (g in germ) ? germ[g] : ""
            else if (k == "mim_phenotype_id") v = (e in phen) ? phen[e] : ""
            else if (k in col)                v = $col[k]
            s = s (i > 1 ? "\t" : "") v
        }
        print s
    }' | gzip -c > "$D/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz"

# --------------------------------------------------------------------------
# bedmap + tag sidecar, both generated from $FIELDS so they cannot drift
# --------------------------------------------------------------------------
{ printf 'index\tname\n'
  i=0; for f in $FIELDS; do printf '%d\t%s\n' "$i" "$f"; i=$((i+1)); done
} | gzip -c > "$D/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz"

FMT=$(for f in $FIELDS; do printf '<%s>|' "$(echo "$f" | tr '[:upper:]' '[:lower:]')"; done | sed 's/|$//')
cat > "$B/gene_transcript_xref.vcfanno.vcf_info_tags.txt" <<TAGS
##INFO=<ID=GENE_TRANSCRIPT_XREF,Number=.,Type=String,Description="Functional gene/transcript annotations. Format: $FMT. Cancer syndrome/susceptibility annotations are listed with MedGen/UMLS concept identifiers. The panel IDs from Genomics England PanelApp are formatted as <panel_id>:<confidence_level>:<panel_version>:<mechanism_of_inheritance>, multiple entries are separated by '&'">
TAGS

# --------------------------------------------------------------------------
log "verification"
printf '  bed records        : %s (prior bundle: %s)\n' \
    "$(zcat "$B/gene_transcript_xref.bed.gz" | wc -l)" \
    "$(zcat "$OLD/gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz" | wc -l)"
printf '  pc_nopad records   : %s\n' "$(zcat "$B/gene_transcript_xref_pc_nopad.bed.gz" | wc -l)"
printf '  field count        : %s (must be 34)\n' \
    "$(zcat "$B/gene_transcript_xref.bed.gz" | head -1 | awk -F'\t' '{print split($4,a,"|")}')"
zcat "$B/gene_transcript_xref.bed.gz" | awk -F'\t' '
    {n=split($4,a,"|"); if(a[22]!="")t++; if(a[23]!="")s++; if(a[24]!="")g++; if(a[34]!="")m++}
    END{printf "  cgc_tier=%d cgc_somatic=%d cgc_germline=%d mim_phenotype=%d\n",t,s,g,m}'
printf '  sample record with CGC:\n'
zcat "$B/gene_transcript_xref.bed.gz" | awk -F'\t' '{n=split($4,a,"|"); if(a[22]!=""){printf "    %s tier=%s som=%s germ=%s mim=%s\n",a[4],a[22],a[23],a[24],a[34]; c++}} c>=2{exit}'
log "done"
