#!/usr/bin/env bash
#
# Diff the bundle's declared VEP tags against what VEP ACTUALLY emits.
#
#   usage: check_csq_tags.sh <container> <vep_cache_dir> <assembly> <vcf_infotags_vep.tsv>
#   e.g.   check_csq_tags.sh ghcr.io/biocentric/gvanno-nf:2026.1 \
#              /mnt/big/gvanno-build/ref-trackb/data/grch38/.vep GRCh38 \
#              refdata-builder/spec/vcf_infotags_vep.tsv
#
# This is the check that was missing. Going from VEP 110 to 115, Ensembl renamed
# the gnomAD "other" population (gnomAD*_OTH_AF -> gnomAD*_REMAINING_AF, in VEP
# 113) and added gnomADe_MID_AF. Nothing in the build would have noticed: the
# declared-but-unemitted columns come out empty and the emitted-but-undeclared
# ones are dropped, on a run that reports success.
#
# check_bundle.py validates structure. This validates the bundle against
# REALITY, by running the actual VEP in the actual container.
#
# Exit 1 on any mismatch that matters.
#
set -uo pipefail

IMAGE=${1:?container image}
CACHE=${2:?vep cache dir}
ASM=${3:-GRCh38}
SPEC=${4:?path to vcf_infotags_vep.tsv}

case $ASM in
    GRCh38) CHROM=7; POS=140753336; REF=A; ALT=T; GNOMADG="--af_gnomadg" ;;
    GRCh37) CHROM=7; POS=140453136; REF=A; ALT=T; GNOMADG="" ;;  # no gnomAD genomes on GRCh37
    *) echo "unknown assembly $ASM" >&2; exit 2 ;;
esac

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n%s\t%s\t.\t%s\t%s\t.\t.\t.\n' \
    "$CHROM" "$POS" "$REF" "$ALT" > "$tmp/probe.vcf"

echo "[csq] running VEP in $IMAGE against $CACHE ($ASM)"
docker run --rm -v "$CACHE":/cache:ro -v "$tmp":/t --entrypoint /bin/bash "$IMAGE" -c "
  vep --input_file /t/probe.vcf --output_file /t/out.vcf \
      --dir /cache --assembly $ASM --cache_version 115 \
      --fasta /cache/homo_sapiens/115_${ASM}/Homo_sapiens.${ASM}.dna.primary_assembly.fa.gz \
      --hgvs --af_gnomad $GNOMADG --variant_class --domains --symbol --protein --ccds --mane \
      --uniprot --appris --biotype --tsl --canonical --format vcf --cache --numbers \
      --total_length --allele_number --failed 1 --no_stats --no_escape --xref_refseq --vcf \
      --check_ref --dont_skip --flag_pick_allele_gene --force_overwrite --species homo_sapiens \
      --offline --quiet >/dev/null 2>&1
  grep -m1 'ID=CSQ' /t/out.vcf | sed 's/.*Format: //; s/\">//' | tr '|' '\n'
" > "$tmp/emitted.txt" || { echo "[csq] VEP run failed" >&2; exit 1; }

[ -s "$tmp/emitted.txt" ] || { echo "[csq] no CSQ header produced — VEP or cache problem" >&2; exit 1; }

# gvanno deliberately consumes only a subset of CSQ (annoutils.py filters by a
# wanted-set), so "not declared" is usually intentional rather than a bug. This
# allowlist records the intentional ones WITH their reason, so anything outside
# it is a genuine finding instead of noise. Do not add to it to silence the
# check — add only when the field is genuinely not wanted.
cat > "$tmp/ignore.txt" <<'IGNORE'
Allele
CHECK_REF
CLIN_SIG
MANE
SOMATIC
UNIPROT_ISOFORM
IGNORE
# Allele          — the ALT itself; carried in the VCF columns already
# CHECK_REF       — QC output of --check_ref, not an annotation
# CLIN_SIG        — VEP's own clinical significance; gvanno uses its curated
#                   ClinVar bundle instead, so surfacing both would conflict
# SOMATIC         — same rationale as CLIN_SIG
# UNIPROT_ISOFORM — gvanno declares UNIPROT_ID / UNIPROT_ACC instead
# MANE            — newly POPULATED in VEP 115 (in 110 the field existed in the
#                   header but was never assigned), so it was flagged and
#                   reviewed rather than assumed. Ignored because it is
#                   redundant: it is the concatenation of MANE_SELECT and
#                   MANE_PLUS_CLINICAL, both already declared here (lines 24-25)
#                   and surfaced as TRANSCRIPT_MANE_SELECT /
#                   TRANSCRIPT_MANE_PLUS_CLINICAL. Adding it would add a column
#                   carrying no new information.

awk -F'\t' 'NR>1 && $1!="" {print $1}' "$SPEC" | sort -u > "$tmp/declared.txt"
sort -u "$tmp/emitted.txt" | grep -v '^$' > "$tmp/emit.txt"
sort -u "$tmp/ignore.txt" > "$tmp/ign.txt"

echo "[csq] VEP emits $(wc -l < "$tmp/emit.txt") CSQ fields; spec declares $(wc -l < "$tmp/declared.txt") tags"

undeclared=$(comm -23 "$tmp/emit.txt" "$tmp/declared.txt" | comm -23 - "$tmp/ign.txt")
# a declared gnomAD tag that VEP does not emit will always be empty
ghost=$(grep -E '^gnomAD' "$tmp/declared.txt" | sort -u | comm -23 - "$tmp/emit.txt")

rc=0
if [ -n "$undeclared" ]; then
    echo "[csq] EMITTED BUT NOT DECLARED — these columns are dropped:"
    echo "$undeclared" | sed 's/^/    /'; rc=1
fi
if [ -n "$ghost" ]; then
    echo "[csq] DECLARED BUT NOT EMITTED — these columns are permanently empty:"
    echo "$ghost" | sed 's/^/    /'; rc=1
fi
[ $rc -eq 0 ] && echo "[csq] OK — every emitted field is declared, no ghost gnomAD tags"
exit $rc
