#!/usr/bin/env bash
#
# Capture the bundle format contract from an extracted gvanno reference bundle.
#
# The rebuilt bundle must reproduce these paths, INFO tag names and column
# layouts exactly, or the sigven/gvanno helpers fail — or, in the dbNSFP case,
# silently emit nothing. Re-run this against any bundle to regenerate spec/.
#
#   usage: capture-spec.sh <extracted_bundle>/data/<assembly> [outdir]
#
set -uo pipefail

SRC=${1:?usage: capture-spec.sh <bundle>/data/<assembly> [outdir]}
SPEC=${2:-spec}

[ -d "$SRC" ] || { echo "no such directory: $SRC" >&2; exit 1; }

rm -rf "$SPEC"
mkdir -p "$SPEC"/{vcfanno_tags,vcf_headers,tsv_headers,bed_layout}
cd "$SRC" || exit 1
SPEC=$(cd - >/dev/null && cd "$SPEC" && pwd)

# 1. vcfanno INFO-tag sidecars — the bundle <-> container contract
find . -name '*.vcfanno.vcf_info_tags.txt' -not -name '._*' \
     -exec cp {} "$SPEC/vcfanno_tags/" \;

# 2. INFO tag dictionaries + version manifest
cp vcf_infotags_gvanno.tsv vcf_infotags_vep.tsv RELEASE_NOTES "$SPEC/" 2>/dev/null

# 3. VCF headers of each vcfanno source
for t in clinvar dbnsfp gwas; do
    [ -f "variant/vcf/$t/$t.vcf.gz" ] || continue
    zcat "variant/vcf/$t/$t.vcf.gz" | sed -n '/^#/p' > "$SPEC/vcf_headers/$t.header.vcf"
done

# 4. tabular column layouts (header row + row count)
[ -f gene/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz ] && \
    zcat gene/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz \
       > "$SPEC/tsv_headers/gene_transcript_xref_bedmap.tsv"

for f in misc/tsv/hotspot/hotspot.tsv.gz \
         misc/tsv/hotspot/hotspot_long.tsv.gz \
         misc/tsv/protein_domain/protein_domain.tsv.gz \
         gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz \
         variant/tsv/clinvar/clinvar.tsv.gz ; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .gz)
    { zcat "$f" | head -1; echo "# rows: $(zcat "$f" | wc -l)"; } > "$SPEC/tsv_headers/$n.header"
done

# 5. BED layouts — column count plus two sample records
for f in gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz \
         gene/bed/gene_transcript_xref/gene_transcript_xref_pc_nopad.bed.gz \
         misc/bed/ncer/ncer.bed.gz ; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .gz)
    { echo "# columns: $(zcat "$f" | head -1 | awk -F'\t' '{print NF}')"
      zcat "$f" | head -2; } > "$SPEC/bed_layout/$n.sample"
done

# 6. full inventory with sizes (AppleDouble sidecars in the upstream tarball
#    are macOS artefacts — excluded, and not to be reproduced)
find . -type f -not -path './.vep/*' -not -name '._*' -printf '%10s  %p\n' \
    | sort -k2 > "$SPEC/INVENTORY.txt"

echo "[spec] captured to $SPEC"
find "$SPEC" -type f | sort
