#!/usr/bin/env bash
#
# Compare two pipeline runs of the same input against different bundles.
#
#   usage: compare_runs.sh <baseline.pass.tsv.gz> <new.pass.tsv.gz>
#
# Rows are JOINED on (CHROM, POS, REF, ALT, Feature), not compared positionally.
#
# This matters. An earlier version hashed each column top-to-bottom and diffed
# the hashes; a single extra row in one file shifts everything below it, so all
# seven "must not drift" columns reported FAIL when in truth zero rows differed.
# Never compare these files by column hash or by line order.
#
# Exit 0 if every invariant holds.
#
set -uo pipefail

OLD=${1:?usage: compare_runs.sh <baseline.pass.tsv.gz> <new.pass.tsv.gz>}
NEW=${2:?usage: compare_runs.sh <baseline.pass.tsv.gz> <new.pass.tsv.gz>}

# Columns that must not move: VEP produces them and Track A does not touch VEP,
# and ncER is carried forward byte-for-byte. Drift here means the bundle
# rebuild corrupted something.
INVARIANT="SYMBOL HGVSp_short CONSEQUENCE Feature ENSEMBL_GENE_ID DBSNPRSID NCER_PERCENTILE"
# Columns expected to change -- reported, never failed on.
EXPECTED="CLINVAR_MSID CLINVAR_CLASSIFICATION CLINVAR_PMID EFFECT_PREDICTIONS DBNSFP_SIFT GWAS_HIT"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

key() { zcat "$1" | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)h[$i]=i;next}
        {print $h["CHROM"]"|"$h["POS"]"|"$h["REF"]"|"$h["ALT"]"|"$h["Feature"]}' | sort; }
pull() { zcat "$1" | awk -F'\t' -v C="$2" 'NR==1{for(i=1;i<=NF;i++)h[$i]=i;next}
         {print $h["CHROM"]"|"$h["POS"]"|"$h["REF"]"|"$h["ALT"]"|"$h["Feature"]"\t"(h[C]?$h[C]:"")}' | sort; }

printf 'baseline %s cols x %s rows\n' \
  "$(zcat "$OLD"|head -1|awk -F'\t' '{print NF}')" "$(( $(zcat "$OLD"|wc -l)-1 ))"
printf 'new      %s cols x %s rows\n\n' \
  "$(zcat "$NEW"|head -1|awk -F'\t' '{print NF}')" "$(( $(zcat "$NEW"|wc -l)-1 ))"

key "$OLD" > "$tmp/ko"; key "$NEW" > "$tmp/kn"
lost=$(comm -23 "$tmp/ko" "$tmp/kn" | wc -l)
gained=$(comm -13 "$tmp/ko" "$tmp/kn" | wc -l)
shared=$(comm -12 "$tmp/ko" "$tmp/kn" | wc -l)
printf 'row sets: shared=%s lost=%s gained=%s\n' "$shared" "$lost" "$gained"
[ "$lost" -gt 0 ]   && { echo "  rows only in baseline:"; comm -23 "$tmp/ko" "$tmp/kn" | head -5 | sed 's/^/    /'; }
[ "$gained" -gt 0 ] && { echo "  rows only in new:";      comm -13 "$tmp/ko" "$tmp/kn" | head -5 | sed 's/^/    /'; }

echo
echo "invariant columns (must not drift on shared rows):"
for c in $INVARIANT; do
    pull "$OLD" "$c" > "$tmp/a"; pull "$NEW" "$c" > "$tmp/b"
    n=$(join -t$'\t' "$tmp/a" "$tmp/b" | awk -F'\t' '$2!=$3{d++}END{print d+0}')
    t=$(join -t$'\t' "$tmp/a" "$tmp/b" | wc -l)
    if [ "$n" -eq 0 ]; then printf '  PASS  %-20s 0/%s differ\n' "$c" "$t"
    else printf '  FAIL  %-20s %s/%s differ\n' "$c" "$n" "$t"; fail=1; fi
done

echo
echo "expected-drift columns (reported, not failed on):"
for c in $EXPECTED; do
    o=$(zcat "$OLD"|awk -F'\t' -v C=$c 'NR==1{for(i=1;i<=NF;i++)if($i==C)k=i;next}k&&$k!=""&&$k!="."{n++}END{print n+0}')
    n=$(zcat "$NEW"|awk -F'\t' -v C=$c 'NR==1{for(i=1;i<=NF;i++)if($i==C)k=i;next}k&&$k!=""&&$k!="."{n++}END{print n+0}')
    printf '  %-24s old=%-6s new=%-6s %+d\n' "$c" "$o" "$n" "$((n-o))"
done

echo
echo "canaries:"
e=$(zcat "$NEW"|awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="EFFECT_PREDICTIONS")k=i;next}k&&$k!=""&&$k!="."{n++}END{print n+0}')
if [ "$e" -gt 0 ]; then printf '  PASS  EFFECT_PREDICTIONS populated on %s rows\n' "$e"
else printf '  FAIL  EFFECT_PREDICTIONS empty everywhere — dbNSFP field-count mismatch\n'; fail=1; fi
bad=$(zcat "$NEW"|awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="CLINVAR_CLNSIG")k=i;next}k&&$k~/^C[N0-9]+:/{n++}END{print n+0}')
if [ "$bad" -eq 0 ]; then printf '  PASS  CLINVAR_CLNSIG grammar is plain\n'
else printf '  FAIL  %s rows use the CUI:significance:count encoding (PCGR donor leaked in)\n' "$bad"; fail=1; fi

echo
[ $fail -eq 0 ] && echo "GATE PASSED" || echo "GATE FAILED"
exit $fail
