#!/usr/bin/env python3
"""
Build a large validation VCF by sampling real ClinVar variants.

The 11-variant fixture is too thin to trust a whole-bundle swap — it is mostly
somatic hotspots and it missed nothing when PCGR's ClinVar turned out to be
dropping germline records. This samples broadly and stratified so the check
actually exercises the annotation paths that matter:

  * pathogenic / likely-pathogenic  — the clinically load-bearing set
  * benign / likely-benign          — the other end of the five-tier scale
  * VUS                             — the largest class by far
  * spread across distinct genes    — avoids over-weighting one locus
  * SNVs only, ALT present          — indels round-trip differently through
                                      VEP normalisation and would muddy a
                                      like-for-like comparison

Sampling from the PRIOR bundle's ClinVar (not the new one) is deliberate: every
variant is then guaranteed to have been annotatable before, so any loss in the
new bundle is a real regression rather than an artefact of the input choice.

  usage: make_check_panel.py --clinvar <old clinvar.vcf.gz> --out panel.vcf
                             [--per-class 250] [--assembly GRCh38]
"""
import argparse
import gzip
import random
import re
import sys
from collections import defaultdict

CLASSES = ['Pathogenic', 'Likely_Pathogenic', 'VUS', 'Likely_Benign', 'Benign']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--clinvar', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--per-class', type=int, default=250)
    ap.add_argument('--assembly', default='GRCh38')
    ap.add_argument('--seed', type=int, default=20260801)
    a = ap.parse_args()

    rng = random.Random(a.seed)          # fixed seed: the panel is reproducible
    pools = defaultdict(list)
    genes_seen = defaultdict(set)

    with gzip.open(a.clinvar, 'rt', errors='replace') as fh:
        for line in fh:
            if line.startswith('#'):
                continue
            f = line.rstrip('\n').split('\t')
            if len(f) < 8:
                continue
            chrom, pos, ref, alt, info = f[0], f[1], f[3], f[4], f[7]
            if len(ref) != 1 or len(alt) != 1 or alt in '.N' or ref in '.N':
                continue
            m = re.search(r'CLINVAR_CLASSIFICATION=([A-Za-z_]+)', info)
            if not m or m.group(1) not in CLASSES:
                continue
            cls = m.group(1)
            g = re.search(r'CLINVAR_ENTREZGENE=(\d+)', info)
            gene = g.group(1) if g else ''
            # one variant per gene per class keeps the panel broad
            if gene and gene in genes_seen[cls]:
                continue
            if gene:
                genes_seen[cls].add(gene)
            msid = re.search(r'CLINVAR_MSID=(\d+)', info)
            pools[cls].append((chrom, pos, ref, alt, msid.group(1) if msid else '.', gene))

    total = 0
    with open(a.out, 'w') as out:
        out.write('##fileformat=VCFv4.2\n')
        out.write('##source=gvanno-nf validation panel (sampled from ClinVar)\n')
        out.write('##reference=%s\n' % a.assembly)
        out.write('##INFO=<ID=EXPECT_MSID,Number=1,Type=String,Description="ClinVar VariationID expected from the prior bundle">\n')
        out.write('##INFO=<ID=EXPECT_CLASS,Number=1,Type=String,Description="ClinVar classification expected from the prior bundle">\n')
        out.write('##INFO=<ID=EXPECT_GENE,Number=1,Type=String,Description="Entrez gene expected from the prior bundle">\n')
        out.write('#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n')

        rows = []
        for cls in CLASSES:
            pool = pools[cls]
            take = min(a.per_class, len(pool))
            sys.stderr.write('  %-18s pool=%-7d taking %d\n' % (cls, len(pool), take))
            rows.extend((v, cls) for v in rng.sample(pool, take))

        def key(r):
            c = r[0][0]
            return (int(c) if c.isdigit() else 99, int(r[0][1]))
        rows.sort(key=key)

        for (chrom, pos, ref, alt, msid, gene), cls in rows:
            out.write('%s\t%s\t.\t%s\t%s\t.\t.\tEXPECT_MSID=%s;EXPECT_CLASS=%s;EXPECT_GENE=%s\n'
                      % (chrom, pos, ref, alt, msid, cls, gene or '.'))
            total += 1

    sys.stderr.write('wrote %s: %d variants across %d genes\n'
                     % (a.out, total, len(set().union(*genes_seen.values()))))


if __name__ == '__main__':
    main()
