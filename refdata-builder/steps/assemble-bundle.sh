#!/usr/bin/env bash
#
# Assemble a gvanno reference bundle from the donor bundles.
#
#   usage: assemble-bundle.sh [-a ASSEMBLY] [-v VERSION] [-o OUTDIR]
#
# Covers the resources that come from donors. The gene/transcript xref is built
# separately (build-gene-xref.sh) because it needs the CGC and MIM maps merged
# in; run this first, then that.
#
#   lift        hotspot, hotspot_long, gwas, dbnsfp   (layout-identical)
#   transform   clinvar vcf (tag rename), clinvar tsv + protein_domain (project)
#   carry       ncer  (PCGR dropped it; no newer release exists anyway)
#   generate    RELEASE_NOTES, the DBNSFP_* block of vcf_infotags_gvanno.tsv
#
# Anything layout-sensitive is resolved by NAME, never by column position.
#
set -uo pipefail

ASM=grch38
VERSION=20260801
OUT=/mnt/big/gvanno-build/bundle
SRC=/mnt/big/gvanno-refdata
BUILD=/mnt/big/gvanno-build
STEPOUT=
CONTAINER=sigven/gvanno:1.7.0

while getopts ":a:v:o:s:h" opt; do
    case $opt in
        a) ASM=$OPTARG ;;
        v) VERSION=$OPTARG ;;
        o) OUT=$OPTARG ;;
        s) STEPOUT=$OPTARG ;;   # dir holding this assembly's built inputs
        h) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done
# Per-assembly step outputs. Defaults to $BUILD/out for grch38 and
# $BUILD/out<NN> otherwise, so the two assemblies never share a directory.
# An earlier version symlinked $BUILD/out per assembly; that silently gave
# GRCh37 the wrong ClinVar when the symlink and the script disagreed.
if [ -z "$STEPOUT" ]; then
    case $ASM in
        grch38) STEPOUT=$BUILD/out ;;
        grch37) STEPOUT=$BUILD/out37 ;;
        *)      STEPOUT=$BUILD/out-$ASM ;;
    esac
fi
[ -d "$STEPOUT" ] || { echo "[assemble] ERROR: no step-output dir $STEPOUT" >&2; exit 1; }
echo "[assemble] assembly=$ASM  step outputs=$STEPOUT"

PCGR=$BUILD/pcgr-20260620/data/$ASM
OLD=$BUILD/ref-20231224/data/$ASM
D=$OUT/data/$ASM

log() { printf '[assemble] %s\n' "$*"; }
die() { printf '[assemble] ERROR: %s\n' "$*" >&2; exit 1; }

[ -d "$PCGR" ] || die "donor not extracted: $PCGR"
[ -d "$OLD" ]  || die "prior bundle not extracted: $OLD"

mkdir -p "$D"/{variant/vcf/{clinvar,dbnsfp,gwas},variant/tsv/clinvar} \
         "$D"/{gene/bed/gene_transcript_xref,gene/tsv/gene_transcript_xref} \
         "$D"/misc/{bed/ncer,tsv/hotspot,tsv/protein_domain} || die "mkdir failed"

# --------------------------------------------------------------------------
# 1. straight lifts — verified layout-identical in spec/DONOR-ASSESSMENT.md
# --------------------------------------------------------------------------
lift() {  # lift <relpath> [<relpath>...]
    for r in "$@"; do
        [ -f "$PCGR/$r" ] || { log "skip (absent in donor): $r"; continue; }
        cp -f "$PCGR/$r" "$D/$r" && log "lift    $r ($(du -h "$D/$r" | cut -f1))"
    done
}
lift misc/tsv/hotspot/hotspot.tsv.gz \
     misc/tsv/hotspot/hotspot_long.tsv.gz \
     variant/vcf/gwas/gwas.vcf.gz \
     variant/vcf/gwas/gwas.vcf.gz.tbi \
     variant/vcf/gwas/gwas.vcfanno.vcf_info_tags.txt \
     variant/vcf/dbnsfp/dbnsfp.vcf.gz \
     variant/vcf/dbnsfp/dbnsfp.vcf.gz.tbi \
     variant/vcf/dbnsfp/dbnsfp.vcfanno.vcf_info_tags.txt

# --------------------------------------------------------------------------
# 2. ncER — carry forward verbatim (2.7 GB; hardlink when on one filesystem)
# --------------------------------------------------------------------------
for f in ncer.bed.gz ncer.bed.gz.tbi ncer.vcfanno.vcf_info_tags.txt; do
    [ -f "$OLD/misc/bed/ncer/$f" ] || die "missing from prior bundle: $f"
    ln -f "$OLD/misc/bed/ncer/$f" "$D/misc/bed/ncer/$f" 2>/dev/null \
        || cp -f "$OLD/misc/bed/ncer/$f" "$D/misc/bed/ncer/$f"
done
log "carry   ncer ($(du -h "$D/misc/bed/ncer/ncer.bed.gz" | cut -f1), from 20231224)"

# --------------------------------------------------------------------------
# 3. ClinVar VCF.
#
#    NOTE: the donor path below is retained only as a fallback. ClinVar should
#    be built from NCBI with build-clinvar.py (`make clinvar`), because PCGR is
#    a somatic annotator and its ClinVar VCF is missing germline records this
#    pipeline needs -- the gate caught F5 p.R534Q (Factor V Leiden,
#    VariationID 642, expert-panel Pathogenic) absent from it while present in
#    the 20231224 bundle. If $BUILD/out/clinvar.final.vcf.gz exists, use it.
# --------------------------------------------------------------------------
if [ -f "$STEPOUT/clinvar.final.vcf.gz" ]; then
    log "install clinvar from NCBI build: $STEPOUT/clinvar.final.vcf.gz"
    cp -f "$STEPOUT/clinvar.final.vcf.gz"     "$D/variant/vcf/clinvar/clinvar.vcf.gz"
    cp -f "$STEPOUT/clinvar.final.vcf.gz.tbi" "$D/variant/vcf/clinvar/clinvar.vcf.gz.tbi"
    cp -f "$STEPOUT/clinvar.tsv.gz"           "$D/variant/tsv/clinvar/clinvar.tsv.gz"
    cp -f "$OLD/variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt" \
          "$D/variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt"
    log "        $(du -h "$D/variant/vcf/clinvar/clinvar.vcf.gz" | cut -f1) vcf, $(du -h "$D/variant/tsv/clinvar/clinvar.tsv.gz" | cut -f1) tsv"
    SKIP_DONOR_CLINVAR=1
else
    die "no NCBI ClinVar at $STEPOUT/clinvar.final.vcf.gz — run 'make clinvar' first.
       Falling back to the PCGR donor is NOT safe: its ClinVar is missing
       germline records (F5 Leiden) and GRCh37 uses an incompatible
       CLINVAR_CLNSIG encoding (CUI:significance:count)."
fi

if [ "${SKIP_DONOR_CLINVAR:-0}" != "1" ]; then
log "WARNING: falling back to the PCGR ClinVar donor — run 'make clinvar' instead"
log "transform clinvar vcf (CLINVAR_GOLD_STARS -> CLINVAR_REVIEW_STATUS_STARS)"
DROP=CLINVAR_CONTRIB_CLNS_GERMLINE,CLINVAR_PHENOTYPE_STATUS
# bcftools in sigven/gvanno:1.7.0 predates --rename-annots, so drop the extra
# tags with -x (which it does support) and do the rename as a stream edit.
# CLINVAR_GOLD_STARS is a distinctive token appearing only as the header ID and
# the INFO key, so a global substitution is safe here.
docker run --rm -v "$BUILD":/w -v "$PCGR":/donor:ro --entrypoint /bin/bash "$CONTAINER" -c "
    set -euo pipefail
    bcftools annotate -x INFO/$DROP -O v /donor/variant/vcf/clinvar/clinvar.vcf.gz \
      | sed 's/CLINVAR_GOLD_STARS/CLINVAR_REVIEW_STATUS_STARS/g' \
      | bgzip -c > /w/clinvar.tmp.vcf.gz
    tabix -f -p vcf /w/clinvar.tmp.vcf.gz
" || die "bcftools clinvar transform failed"
mv -f "$BUILD/clinvar.tmp.vcf.gz"     "$D/variant/vcf/clinvar/clinvar.vcf.gz"
mv -f "$BUILD/clinvar.tmp.vcf.gz.tbi" "$D/variant/vcf/clinvar/clinvar.vcf.gz.tbi"

# tag sidecar: same rename, same drops
grep -v -E "ID=($(echo "$DROP" | tr ',' '|'))," \
    "$PCGR/variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt" \
  | sed 's/ID=CLINVAR_GOLD_STARS/ID=CLINVAR_REVIEW_STATUS_STARS/' \
  > "$D/variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt"
log "        clinvar tags: $(grep -c '^##INFO' "$D/variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt") (expect 16)"

# --------------------------------------------------------------------------
# 4. ClinVar TSV — project onto the columns gvanno_finalize.py reads.
#    PCGR renamed num_submitters -> num_submissions and dropped
#    nontruncating_variant; emit both under the names gvanno expects.
# --------------------------------------------------------------------------
log "transform clinvar tsv (column projection)"
zcat "$OLD/variant/tsv/clinvar/clinvar.tsv.gz" | head -1 > "$BUILD/clinvar_cols.txt"
zcat "$PCGR/variant/tsv/clinvar/clinvar.tsv.gz" \
  | awk -F'\t' -v want="$(cat "$BUILD/clinvar_cols.txt")" '
    BEGIN { n = split(want, w, "\t") }
    NR == 1 {
        for (i = 1; i <= NF; i++) c[$i] = i
        c["num_submitters"]        = c["num_submitters"]        ? c["num_submitters"]        : c["num_submissions"]
        c["nontruncating_variant"] = c["nontruncating_variant"] ? c["nontruncating_variant"] : 0
        for (i = 1; i <= n; i++) if (!(w[i] in c)) miss = miss " " w[i]
        if (miss != "") printf "  note: not in donor, emitted empty:%s\n", miss > "/dev/stderr"
        print want; next
    }
    { s = ""
      for (i = 1; i <= n; i++) { k = c[w[i]]; s = s (i > 1 ? "\t" : "") (k ? $k : "") }
      print s }
  ' 2>"$BUILD/clinvar_tsv.warn" | gzip -c > "$D/variant/tsv/clinvar/clinvar.tsv.gz"
[ -s "$BUILD/clinvar_tsv.warn" ] && cat "$BUILD/clinvar_tsv.warn"
log "        clinvar tsv rows: $(zcat "$D/variant/tsv/clinvar/clinvar.tsv.gz" | wc -l)"
fi   # end donor-ClinVar fallback

# --------------------------------------------------------------------------
# 5. protein_domain — PCGR carries 5 columns, gvanno wants 3, deduped
# --------------------------------------------------------------------------
log "transform protein_domain (5 cols -> 3, deduped)"
zcat "$PCGR/misc/tsv/protein_domain/protein_domain.tsv.gz" \
  | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)c[$i]=i; print "pfam_id\tpfam_name\tpfam_link"; next}
      { k=$c["pfam_id"]; if(k=="" || k in seen) next; seen[k]=1
        print $c["pfam_id"]"\t"$c["pfam_name"]"\t"$c["pfam_link"] }' \
  | gzip -c > "$D/misc/tsv/protein_domain/protein_domain.tsv.gz"
log "        pfam entries: $(( $(zcat "$D/misc/tsv/protein_domain/protein_domain.tsv.gz" | wc -l) - 1 ))"

# --------------------------------------------------------------------------
# 6. vcf_infotags — carry the DBNSFP_* block over UNCHANGED.
#
#    An earlier version generated these names from the donor's Format string.
#    That is wrong. dbnsfp.py discovers the *algorithm list* dynamically from
#    the header, but maps each one to an output tag through a HARDCODED
#    17-entry algo_mapping dict in the container:
#
#        'gerp_rs' -> 'DBNSFP_GERP'      (not DBNSFP_GERP_RS)
#        'aloft'   -> 'DBNSFP_ALOFTPRED'
#        'metarnn' -> 'DBNSFP_META_RNN'  ... etc
#
#    Derived names miss, and cyvcf2 raises on an undeclared INFO tag:
#        Exception: not able to set: DBNSFP_GERP -> 5.08 (-1)
#
#    So the emittable tag set is fixed by the container, not by the data. The
#    prior bundle's 17 declarations already match algo_mapping exactly — copy
#    them. dbNSFP v5.3's new predictors (AlphaMissense, REVEL, CADD, ...) are
#    still parsed and still appear in the combined EFFECT_PREDICTIONS string;
#    they simply get no column of their own until Track B rebuilds the
#    container. The four predictors v5.3 drops leave their tags declared but
#    unpopulated, which is harmless.
# --------------------------------------------------------------------------
log "generate  vcf_infotags_gvanno.tsv (DBNSFP_* block carried over verbatim)"
cp -f "$OLD/vcf_infotags_gvanno.tsv" "$D/vcf_infotags_gvanno.tsv"
cp -f "$OLD/vcf_infotags_vep.tsv"    "$D/vcf_infotags_vep.tsv"
log "        DBNSFP_* tags declared: $(grep -c '^DBNSFP_' "$D/vcf_infotags_gvanno.tsv") (fixed by the container's algo_mapping)"

# --------------------------------------------------------------------------
# 7. RELEASE_NOTES
# --------------------------------------------------------------------------
cat > "$D/RELEASE_NOTES" <<NOTES
##GVANNO_SOFTWARE_VERSION = 1.7.0
##GVANNO_DB_VERSION = $VERSION
pfam = from PCGR 20260620
ncER = v1.0 (March 2019)
uniprot = from PCGR 20260620
cancerhotspots = v3 (2026)
dbsnp = build 154
dbnsfp = v5.3 (October 2025)
gnomad = r2.1 (October 2018)
gwas = from PCGR 20260620
clinvar = 2026-07-28 (NCBI direct)
gencode = 44/19
cgc = v101 (2025, via PCGR 20250314)
mim_phenotype = NCBI mim2gene_medgen unioned with 20231224
NOTES
log "generate  RELEASE_NOTES ($VERSION)"

log "done. Next: build-gene-xref.sh, then verify/check_bundle.py"
find "$D" -type f | sort | sed 's|^|  |'
