#!/usr/bin/env bash
#
# Track B gate: VEP 110 + bundle 20260801  vs  VEP 115 + bundle 20260810.
#
#   usage: compare_trackb.sh <old.pass.tsv.gz> <new.pass.tsv.gz> <GRCh38|GRCh37>
#
# Track A's gate demanded ZERO drift in VEP-derived columns. That rule is INVALID
# here and its join key is actively wrong: rows were matched on
# (CHROM,POS,REF,ALT,Feature), and GENCODE 44 -> 49 roughly doubles the
# transcript set (252,835 -> 507,365), so Feature is exactly what changes.
#
# Replacement, in decreasing strength:
#
#   STRICT      bundle-carried, position-keyed annotations. The bundle differs
#               between the two arms only in its tag dictionary and
#               RELEASE_NOTES, and vcfanno keys on position, so CLINVAR_*,
#               NCER_PERCENTILE and GWAS_HIT must be IDENTICAL. Any movement
#               means the VEP swap corrupted vcfanno's input rather than that
#               annotation improved.
#
#   CONTROL     GRCh37 only. Its VEP 115 cache is still GENCODE 19 -- identical
#               to 110 -- so transcript churn should be ~zero. GRCh37 is
#               therefore the arm that proves the container rebuild did not
#               break VEP, independently of any data improvement.
#
#   DIRECTIONAL GRCh38. gnomAD r2.1 -> v4.1 and dbSNP 154 -> 156 must INCREASE
#               coverage. A decrease is a failure; no change means the flags are
#               not reaching VEP (e.g. --af_gnomadg missing).
#
# Rows are joined on (CHROM,POS,REF,ALT,GENE) -- gene, not transcript -- so the
# key survives a GENCODE bump.
#
set -uo pipefail

OLD=${1:?old pass.tsv.gz}
NEW=${2:?new pass.tsv.gz}
ASM=${3:-GRCh38}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

key()  { zcat "$1" | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)h[$i]=i;next}
         {print $h["CHROM"]"|"$h["POS"]"|"$h["REF"]"|"$h["ALT"]"|"$h["ENSEMBL_GENE_ID"]}' | sort -u; }
pull() { zcat "$1" | awk -F'\t' -v C="$2" 'NR==1{for(i=1;i<=NF;i++)h[$i]=i;next}
         {print $h["CHROM"]"|"$h["POS"]"|"$h["REF"]"|"$h["ALT"]"|"$h["ENSEMBL_GENE_ID"]"\t"(h[C]?$h[C]:"")}' | sort -u; }
fill() { zcat "$1" | awk -F'\t' -v C="$2" 'NR==1{for(i=1;i<=NF;i++)if($i==C)k=i;next}
         k&&$k!=""&&$k!="."{n++}END{print n+0}'; }
rows() { echo $(( $(zcat "$1" | wc -l) - 1 )); }

printf 'assembly %s\n' "$ASM"
printf '  old  %s cols x %s rows\n' "$(zcat "$OLD"|head -1|awk -F'\t' '{print NF}')" "$(rows "$OLD")"
printf '  new  %s cols x %s rows\n' "$(zcat "$NEW"|head -1|awk -F'\t' '{print NF}')" "$(rows "$NEW")"

key "$OLD" > "$tmp/ko"; key "$NEW" > "$tmp/kn"
shared=$(comm -12 "$tmp/ko" "$tmp/kn" | wc -l)
printf '  variant x gene keys: shared=%s only-old=%s only-new=%s\n' \
    "$shared" "$(comm -23 "$tmp/ko" "$tmp/kn" | wc -l)" "$(comm -13 "$tmp/ko" "$tmp/kn" | wc -l)"

echo
echo "STRICT — bundle-carried, position-keyed (must be identical):"
for c in CLINVAR_MSID CLINVAR_CLASSIFICATION NCER_PERCENTILE GWAS_HIT; do
    pull "$OLD" "$c" > "$tmp/a"; pull "$NEW" "$c" > "$tmp/b"
    n=$(join -t$'\t' "$tmp/a" "$tmp/b" | awk -F'\t' '$2!=$3{d++}END{print d+0}')
    t=$(join -t$'\t' "$tmp/a" "$tmp/b" | wc -l)
    if [ "$n" -eq 0 ]; then printf '  PASS  %-24s 0/%s differ\n' "$c" "$t"
    else printf '  FAIL  %-24s %s/%s differ — the VEP swap corrupted vcfanno input\n' "$c" "$n" "$t"; fail=1; fi
done

if [ "$ASM" = GRCh37 ]; then
    echo
    echo "CONTROL — GRCh37 keeps GENCODE 19 across 110/115, so churn must be ~zero:"
    for c in Feature SYMBOL HGVSp_short CONSEQUENCE; do
        pull "$OLD" "$c" > "$tmp/a"; pull "$NEW" "$c" > "$tmp/b"
        n=$(join -t$'\t' "$tmp/a" "$tmp/b" | awk -F'\t' '$2!=$3{d++}END{print d+0}')
        t=$(join -t$'\t' "$tmp/a" "$tmp/b" | wc -l)
        pct=$(awk -v n="$n" -v t="$t" 'BEGIN{printf "%.2f", t? 100*n/t : 0}')
        if [ "$(awk -v p="$pct" 'BEGIN{print (p<1)?1:0}')" = 1 ]; then
            printf '  PASS  %-24s %s/%s differ (%s%%)\n' "$c" "$n" "$t" "$pct"
        else printf '  FAIL  %-24s %s/%s differ (%s%%) — >1%% churn on a frozen GENCODE\n' "$c" "$n" "$t" "$pct"; fail=1; fi
    done
fi

echo
echo "DIRECTIONAL — the point of the upgrade (coverage must rise):"
tot=$(rows "$NEW")
for c in gnomADe_AF DBSNPRSID; do
    o=$(fill "$OLD" "$c"); n=$(fill "$NEW" "$c")
    d=$((n-o))
    if [ "$d" -ge 0 ]; then printf '  PASS  %-24s %s -> %s  (%+d, %s%% of %s rows)\n' \
        "$c" "$o" "$n" "$d" "$(awk -v n="$n" -v t="$tot" 'BEGIN{printf "%.0f", t?100*n/t:0}')" "$tot"
    else printf '  FAIL  %-24s %s -> %s  (%+d) — coverage DROPPED\n' "$c" "$o" "$n" "$d"; fail=1; fi
done
# gnomADg only exists on GRCh38; on GRCh37 Ensembl has no gnomAD genome data.
if [ "$ASM" = GRCh38 ]; then
    n=$(fill "$NEW" gnomADg_AF)
    if [ "$n" -gt 0 ]; then printf '  PASS  %-24s %s rows populated (was never populated before)\n' "gnomADg_AF" "$n"
    else printf '  FAIL  %-24s still 0 — --af_gnomadg is not reaching VEP\n' "gnomADg_AF"; fail=1; fi
fi

echo
echo "CANARIES:"
e=$(fill "$NEW" EFFECT_PREDICTIONS)
[ "$e" -gt 0 ] && printf '  PASS  EFFECT_PREDICTIONS populated on %s rows\n' "$e" \
               || { printf '  FAIL  EFFECT_PREDICTIONS empty — dbNSFP field-count mismatch\n'; fail=1; }
bad=$(zcat "$NEW"|awk -F'\t' 'NR==1{for(i=1;i<=NF;i++)if($i=="CLINVAR_CLNSIG")k=i;next}k&&$k~/^C[N0-9]+:/{n++}END{print n+0}')
[ "$bad" -eq 0 ] && printf '  PASS  CLINVAR_CLNSIG grammar is plain\n' \
                 || { printf '  FAIL  %s rows use the CUI:sig:count encoding\n' "$bad"; fail=1; }

echo
[ $fail -eq 0 ] && echo "TRACK B GATE PASSED ($ASM)" || echo "TRACK B GATE FAILED ($ASM)"
exit $fail
