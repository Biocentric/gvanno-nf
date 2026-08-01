#!/usr/bin/env python3
"""
Assert a built bundle satisfies the container's contract, BEFORE running the
pipeline against it.

Both failure modes this project hit are silent — the pipeline reports success
and quietly drops annotations — so they cannot be caught by "does it run":

  1. dbNSFP field-count mismatch. dbnsfp.py compares the algorithm count
     declared in the DBNSFP header's Format: string against the fields present
     in each record. On mismatch it returns NO predictions rather than raising,
     so EFFECT_PREDICTIONS and every DBNSFP_* column come out empty.

  2. Undeclared output tags. dbnsfp.py maps algorithms to output tags through a
     HARDCODED 17-entry dict; any DBNSFP_* tag it emits must be declared in
     vcf_infotags_gvanno.tsv or cyvcf2 raises mid-run.

    usage: check_bundle.py <bundle_root> [--assembly grch38] [--version 20260801]
"""
import argparse
import gzip
import os
import re
import sys

# Fixed by lib/gvanno/dbnsfp.py in sigven/gvanno:1.7.0. The emittable tag set
# is a property of the CONTAINER, not of the data.
ALGO_MAPPING_TAGS = {
    'DBNSFP_SIFT', 'DBNSFP_PROVEAN', 'DBNSFP_M_CAP', 'DBNSFP_MUTPRED',
    'DBNSFP_META_RNN', 'DBNSFP_FATHMM', 'DBNSFP_FATHMM_MKL',
    'DBNSFP_MUTATIONASSESSOR', 'DBNSFP_MUTATIONTASTER', 'DBNSFP_DEOGEN2',
    'DBNSFP_PRIMATEAI', 'DBNSFP_LIST_S2', 'DBNSFP_GERP', 'DBNSFP_ALOFTPRED',
    'DBNSFP_BAYESDEL_ADDAF', 'DBNSFP_SPLICE_SITE_ADA', 'DBNSFP_SPLICE_SITE_RF',
}

REQUIRED = [
    'RELEASE_NOTES', 'vcf_infotags_gvanno.tsv', 'vcf_infotags_vep.tsv',
    'variant/vcf/clinvar/clinvar.vcf.gz', 'variant/vcf/clinvar/clinvar.vcf.gz.tbi',
    'variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt',
    'variant/tsv/clinvar/clinvar.tsv.gz',
    'variant/vcf/dbnsfp/dbnsfp.vcf.gz', 'variant/vcf/dbnsfp/dbnsfp.vcf.gz.tbi',
    'variant/vcf/dbnsfp/dbnsfp.vcfanno.vcf_info_tags.txt',
    'variant/vcf/gwas/gwas.vcf.gz', 'variant/vcf/gwas/gwas.vcf.gz.tbi',
    'variant/vcf/gwas/gwas.vcfanno.vcf_info_tags.txt',
    'gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz',
    'gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz.tbi',
    'gene/bed/gene_transcript_xref/gene_transcript_xref_pc_nopad.bed.gz',
    'gene/bed/gene_transcript_xref/gene_transcript_xref.vcfanno.vcf_info_tags.txt',
    'gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz',
    'gene/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz',
    'misc/bed/ncer/ncer.bed.gz', 'misc/bed/ncer/ncer.bed.gz.tbi',
    'misc/bed/ncer/ncer.vcfanno.vcf_info_tags.txt',
    'misc/tsv/hotspot/hotspot.tsv.gz',
    'misc/tsv/protein_domain/protein_domain.tsv.gz',
]

CLINVAR_TAGS = {
    'CLINVAR_MSID', 'CLINVAR_CLNSIG', 'CLINVAR_CLNSIG_SOMATIC', 'CLINVAR_PMID',
    'CLINVAR_ENTREZGENE', 'CLINVAR_PMID_SOMATIC', 'CLINVAR_CONFLICTED',
    'CLINVAR_VARIANT_ORIGIN', 'CLINVAR_NUM_SUBMITTERS', 'CLINVAR_UMLS_CUI',
    'CLINVAR_UMLS_CUI_SOMATIC', 'CLINVAR_CLASSIFICATION', 'CLINVAR_ALLELE_ID',
    'CLINVAR_HGVSP', 'CLINVAR_MOLECULAR_EFFECT', 'CLINVAR_REVIEW_STATUS_STARS',
}

results = []


def check(name, ok, detail=''):
    results.append((name, ok, detail))
    print('  %-4s %-42s %s' % ('PASS' if ok else 'FAIL', name, detail))
    return ok


def head_lines(path, n=200, skip_comment=False):
    op = gzip.open if path.endswith('.gz') else open
    out = []
    with op(path, 'rt', errors='replace') as fh:
        for line in fh:
            if skip_comment and line.startswith('#'):
                continue
            out.append(line.rstrip('\n'))
            if len(out) >= n:
                break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('bundle')
    ap.add_argument('--assembly', default='grch38')
    ap.add_argument('--version')
    a = ap.parse_args()

    d = os.path.join(a.bundle, 'data', a.assembly)
    if not os.path.isdir(d):
        sys.exit('no bundle at %s' % d)
    print('checking %s\n' % d)

    print('files:')
    missing = [p for p in REQUIRED if not os.path.exists(os.path.join(d, p))]
    check('all required files present', not missing,
          '' if not missing else 'missing: %s' % ', '.join(missing[:4]))

    print('\nrelease notes:')
    rel = open(os.path.join(d, 'RELEASE_NOTES')).read()
    m = re.search(r'GVANNO_DB_VERSION = (\S+)', rel)
    check('declares a DB version', bool(m), m.group(1) if m else '')
    if a.version:
        check('version matches --version', bool(m) and m.group(1) == a.version,
              'expected %s' % a.version)

    # --- the dbNSFP contract (failure mode 1) -----------------------------
    print('\ndbNSFP field-count contract:')
    tagfile = os.path.join(d, 'variant/vcf/dbnsfp/dbnsfp.vcfanno.vcf_info_tags.txt')
    fmt = re.search(r'Format: ([^"]+)', open(tagfile).read())
    n_declared = None
    if check('DBNSFP header declares a Format:', bool(fmt)):
        subtags = fmt.group(1).split('|')
        n_declared = len(subtags)
        check('Format has >6 leading fields', n_declared > 6,
              '%d fields = 6 + %d algorithms' % (n_declared, n_declared - 6))
        check('leading fields are the expected six',
              [s.strip().lower() for s in subtags[:6]] ==
              ['refaa', 'altaa', 'codonpos', 'ensembl_gene_id',
               'ensembl_trans_id', 'proteinpos'],
              '|'.join(subtags[:6]))

    counts = set()
    for line in head_lines(os.path.join(d, 'variant/vcf/dbnsfp/dbnsfp.vcf.gz'),
                           n=2000, skip_comment=True):
        f = line.split('\t')
        if len(f) < 8:
            continue
        mm = re.search(r'DBNSFP=([^;\t]+)', f[7])
        if mm:
            for rec in mm.group(1).split(','):
                counts.add(len(rec.split('|')))
    check('data records have a consistent field count', len(counts) == 1,
          'saw %s' % sorted(counts))
    if n_declared and counts:
        check('data field count == header declaration',
              counts == {n_declared},
              'header %d vs data %s — a mismatch SILENTLY empties '
              'EFFECT_PREDICTIONS' % (n_declared, sorted(counts)))

    # --- declared output tags (failure mode 2) ----------------------------
    print('\ndeclared DBNSFP_* output tags:')
    declared = set()
    for line in open(os.path.join(d, 'vcf_infotags_gvanno.tsv')):
        t = line.split('\t')[0]
        if t.startswith('DBNSFP_'):
            declared.add(t)
    undeclared = ALGO_MAPPING_TAGS - declared
    check('every tag the container can emit is declared', not undeclared,
          'undeclared: %s' % ', '.join(sorted(undeclared)) if undeclared
          else '%d tags' % len(declared))

    # --- other tag contracts ---------------------------------------------
    print('\ntag sidecars:')
    cv = set(re.findall(r'ID=(CLINVAR_[A-Z_]+)',
                        open(os.path.join(d, 'variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt')).read()))
    check('ClinVar declares exactly the 16 expected tags', cv == CLINVAR_TAGS,
          'extra: %s missing: %s' % (sorted(cv - CLINVAR_TAGS), sorted(CLINVAR_TAGS - cv))
          if cv != CLINVAR_TAGS else '16 tags')

    xf = os.path.join(d, 'gene/bed/gene_transcript_xref/gene_transcript_xref.vcfanno.vcf_info_tags.txt')
    xm = re.search(r'Format: ([^.]+)', open(xf).read())
    n_x = len(xm.group(1).split('|')) if xm else 0
    check('GENE_TRANSCRIPT_XREF declares 34 fields', n_x == 34, '%d fields' % n_x)

    bed = head_lines(os.path.join(d, 'gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz'), n=500)
    bad = {len(l.split('\t')[3].split('|')) for l in bed if len(l.split('\t')) >= 4}
    check('xref BED records carry 34 fields', bad == {34}, 'saw %s' % sorted(bad))

    bedmap = head_lines(os.path.join(d, 'gene/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz'), n=100)
    check('bedmap has 34 entries + header', len(bedmap) == 35, '%d lines' % len(bedmap))

    print('\nindexes:')
    for p in REQUIRED:
        if p.endswith('.vcf.gz') or p.endswith('.bed.gz'):
            tbi = os.path.join(d, p + '.tbi')
            if os.path.basename(p).startswith('gene_transcript_xref_pc_nopad'):
                continue
            check('index for %s' % os.path.basename(p), os.path.exists(tbi))

    n_fail = sum(1 for _, ok, _ in results if not ok)
    print('\n%d checks, %d failed' % (len(results), n_fail))
    sys.exit(1 if n_fail else 0)


if __name__ == '__main__':
    main()
