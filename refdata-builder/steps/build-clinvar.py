#!/usr/bin/env python3
"""
Build gvanno's clinvar.vcf.gz + clinvar.tsv.gz directly from NCBI ClinVar.

Not lifted from the PCGR donor: PCGR is a somatic annotator and its ClinVar VCF
is missing germline records this pipeline needs. The validation gate caught
F5 p.R534Q (Factor V Leiden, VariationID 642, expert-panel Pathogenic) absent
from it while present in the 20231224 bundle.

Emits exactly the 16 CLINVAR_* tags gvanno declares, in the encoding the
20231224 bundle used -- verified against its F5 Leiden record:

    CLINVAR_MSID=642
    CLINVAR_CLNSIG=drug_response
    CLINVAR_ENTREZGENE=2153
    CLINVAR_UMLS_CUI=C0948008,C0950123,...
    CLINVAR_NUM_SUBMITTERS=17
    CLINVAR_CONFLICTED=0
    CLINVAR_PMID=25741868,27797270
    CLINVAR_VARIANT_ORIGIN=germline
    CLINVAR_MOLECULAR_EFFECT=missense_variant:NM_000130:c.1601G>A:p.Arg534Gln
    CLINVAR_HGVSP=p.Arg534Gln
    CLINVAR_REVIEW_STATUS_STARS=3
    CLINVAR_ALLELE_ID=15681
    CLINVAR_CLASSIFICATION=VUS

Inputs (all account-free, from ftp.ncbi.nlm.nih.gov/pub/clinvar):
    clinvar_<release>.<asm>.vcf.gz   the variant records
    variant_summary.txt.gz           NumberSubmitters, Name (HGVSc/HGVSp/RefSeq)
    var_citations.txt                PubMed IDs
"""
import argparse
import gzip
import os
import re
import sys
from collections import defaultdict

# CLNREVSTAT -> star rating
STARS = {
    'practice_guideline': 4,
    'reviewed_by_expert_panel': 3,
    'criteria_provided,_multiple_submitters,_no_conflicts': 2,
    'criteria_provided,_multiple_submitters': 2,
    'criteria_provided,_conflicting_classifications': 1,
    'criteria_provided,_conflicting_interpretations': 1,
    'criteria_provided,_single_submitter': 1,
    'no_assertion_criteria_provided': 0,
    'no_classification_provided': 0,
    'no_classification_for_the_single_variant': 0,
    'no_assertion_provided': 0,
}

# ClinVar ORIGIN is a bitmask; gvanno only distinguishes germline vs somatic.
ORIGIN_GERMLINE, ORIGIN_SOMATIC = 1, 2


def five_tier(clnsig):
    """Collapse CLNSIG onto gvanno's five-tiered scale.

    Order matters: 'benign,likely_benign' resolves to Benign and
    'pathogenic,likely_pathogenic' to Pathogenic. Verified against the
    20231224 tallies (16528 benign + 3343 both = 19873 Benign).
    Anything non-classifying -- drug_response, risk_factor, conflicting --
    lands in VUS, matching F5 Leiden's own record.
    """
    s = clnsig.lower()
    if re.search(r'(^|[,|/])pathogenic', s):
        return 'Pathogenic'
    if 'likely_pathogenic' in s:
        return 'Likely_Pathogenic'
    if re.search(r'(^|[,|/])benign', s):
        return 'Benign'
    if 'likely_benign' in s:
        return 'Likely_Benign'
    return 'VUS'


def norm_sig(v):
    """NCBI writes Pathogenic/Likely_pathogenic; gvanno writes it lowercased
    and comma-separated."""
    return v.replace('/', ',').replace('|', ',').lower() if v else ''


def parse_info(field):
    d = {}
    for kv in field.split(';'):
        if '=' in kv:
            k, v = kv.split('=', 1)
            d[k] = v
    return d


def load_citations(path, cap=64):
    """VariationID -> PubMed IDs.

    var_citations.txt has SEVEN columns, not four:
        #AlleleID  VariationID  rs  nsv  citation_source  citation_id  organization_ids
    so the key is field 1 and the PMID is field 5. Getting this wrong is
    silent -- the filter simply never matches and every CLINVAR_PMID comes out
    empty -- so assert we loaded something before returning.

    Heavily studied variants carry hundreds of citations (F5 Leiden alone has
    dozens); cap per variant to keep the INFO field usable. The 20231224
    bundle listed only two for F5 Leiden, so this is already more complete.
    """
    cites = defaultdict(set)
    if not path or not os.path.exists(path):
        sys.stderr.write('  note: no var_citations.txt; CLINVAR_PMID empty\n')
        return cites
    with open(path, errors='replace') as fh:
        hdr = fh.readline().lstrip('#').rstrip('\n').split('\t')
        idx = {c: i for i, c in enumerate(hdr)}
        try:
            k_var = idx['VariationID']
            k_src = idx['citation_source']
            k_id = idx['citation_id']
        except KeyError:
            sys.stderr.write('  WARNING: var_citations layout changed: %s\n' % hdr)
            return cites
        for line in fh:
            f = line.rstrip('\n').split('\t')
            if len(f) <= k_id or f[k_src] != 'PubMed':
                continue
            pmid = f[k_id]
            if pmid.isdigit():
                cites[f[k_var]].add(pmid)
    if not cites:
        sys.stderr.write('  WARNING: parsed 0 citations from %s\n' % path)
    else:
        for v in cites:
            if len(cites[v]) > cap:
                cites[v] = set(sorted(cites[v], key=int)[:cap])
    return cites


NAME_RE = re.compile(r'^(N[MRPGC]_[0-9.]+)(?:\([^)]*\))?:([^ ]+)(?:\s+\((p\.[^)]+)\))?')


def load_summary(path, assembly):
    """VariationID -> (num_submitters, refseq, hgvsc, hgvsp)."""
    out = {}
    if not path or not os.path.exists(path):
        sys.stderr.write('  note: no variant_summary; submitters/HGVSp empty\n')
        return out
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt', errors='replace') as fh:
        hdr = fh.readline().lstrip('#').rstrip('\n').split('\t')
        idx = {c: i for i, c in enumerate(hdr)}
        need = ('VariationID', 'Name', 'NumberSubmitters', 'Assembly')
        if not all(c in idx for c in need):
            sys.stderr.write('  note: variant_summary layout changed; skipping\n')
            return out
        for line in fh:
            f = line.rstrip('\n').split('\t')
            if len(f) <= idx['Assembly'] or f[idx['Assembly']] != assembly:
                continue
            vid = f[idx['VariationID']]
            if vid in out:
                continue
            refseq = hgvsc = hgvsp = ''
            m = NAME_RE.match(f[idx['Name']])
            if m:
                refseq = m.group(1).split('.')[0]
                hgvsc = m.group(2)
                hgvsp = m.group(3) or ''
            out[vid] = (f[idx['NumberSubmitters']], refseq, hgvsc, hgvsp)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--vcf', required=True)
    ap.add_argument('--summary')
    ap.add_argument('--citations')
    ap.add_argument('--assembly', default='GRCh38')
    ap.add_argument('--out-vcf', required=True)
    ap.add_argument('--out-tsv', required=True)
    a = ap.parse_args()

    sys.stderr.write('[clinvar] loading citations\n')
    cites = load_citations(a.citations)
    sys.stderr.write('[clinvar] loading variant_summary (%s)\n' % a.assembly)
    summ = load_summary(a.summary, a.assembly)
    sys.stderr.write('[clinvar] citations=%d summary=%d\n' % (len(cites), len(summ)))

    TSV_COLS = ['chrom', 'pos', 'ref', 'alt', 'allele_id', 'variation_id', 'rsid',
                'origin_simple', 'clinical_significance_concensus',
                'review_status_concensus', 'num_submitters', 'no_phenotype',
                'gold_stars', 'conflicted', 'pathogenic', 'benign', 'vus',
                'somatic', 'class4', 'class5', 'class2', 'class1', 'class3',
                'classification', 'variation_type', 'truncating_variant',
                'nontruncating_variant', 'refseq_transcript_id', 'entrezgene',
                'symbol', 'molecular_consequence', 'hgvs_p', 'hgvs_c',
                'hgvs_p_short', 'molecular_effect',
                'clinical_significance_somatic', 'pmid_somatic', 'cui_somatic',
                'trait_somatic', 'cui', 'pmid', 'trait', 'VAR_ID', 'build']

    n_in = n_out = 0
    op = gzip.open if a.vcf.endswith('.gz') else open
    with op(a.vcf, 'rt', errors='replace') as fh, \
            gzip.open(a.out_vcf + '.tmp', 'wt') as vout, \
            gzip.open(a.out_tsv, 'wt') as tout:

        vout.write('##fileformat=VCFv4.2\n')
        vout.write('##source=gvanno-nf refdata-builder from NCBI ClinVar\n')
        vout.write('##reference=%s\n' % a.assembly)
        tout.write('\t'.join(TSV_COLS) + '\n')
        header_done = False

        for line in fh:
            if line.startswith('##'):
                if line.startswith('##contig'):
                    vout.write(line)
                continue
            if line.startswith('#CHROM'):
                continue
            if not header_done:
                # the 16 tags gvanno declares, emitted verbatim from spec/
                for t, num, typ, desc in [
                    ('CLINVAR_MSID', '1', 'Integer', 'ClinVar - Measureset/Variant ID'),
                    ('CLINVAR_ALLELE_ID', '1', 'Integer', 'ClinVaR - allele ID'),
                    ('CLINVAR_CLNSIG', '.', 'String', 'ClinVar - clinical significance'),
                    ('CLINVAR_CLNSIG_SOMATIC', '.', 'String', 'ClinVar - clinical significance - somatic state'),
                    ('CLINVAR_CLASSIFICATION', '.', 'String', 'ClinVar - Clinical significance of variant on a five-tiered scale'),
                    ('CLINVAR_REVIEW_STATUS_STARS', '1', 'Integer', 'ClinVar - Rating of the variant (0-4 stars) with respect to level of review'),
                    ('CLINVAR_NUM_SUBMITTERS', '1', 'Integer', 'ClinVar - number of submitters for variant record'),
                    ('CLINVAR_CONFLICTED', '1', 'Integer', 'ClinVar - conflicting interpretations of record'),
                    ('CLINVAR_ENTREZGENE', '.', 'String', 'ClinVar - record Entrez gene ID'),
                    ('CLINVAR_VARIANT_ORIGIN', '.', 'String', 'ClinVar - variant origin'),
                    ('CLINVAR_UMLS_CUI', '.', 'String', 'ClinVar - Associated UMLS concept unique identifiers (CUI) - germline state'),
                    ('CLINVAR_UMLS_CUI_SOMATIC', '.', 'String', 'ClinVar - Associated UMLS concept unique identifiers - somatic state (CUI)'),
                    ('CLINVAR_PMID', '.', 'Integer', 'ClinVar - PubMed IDs - germline state'),
                    ('CLINVAR_PMID_SOMATIC', '.', 'Integer', 'ClinVar - PubMed IDs - somatic state'),
                    ('CLINVAR_HGVSP', '.', 'String', 'ClinVar - Protein variant identifier - HGVS nomenclature'),
                    ('CLINVAR_MOLECULAR_EFFECT', '.', 'String', 'ClinVar - Molecular effect(s) of variant'),
                ]:
                    vout.write('##INFO=<ID=%s,Number=%s,Type=%s,Description="%s">\n' % (t, num, typ, desc))
                vout.write('#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n')
                header_done = True

            f = line.rstrip('\n').split('\t')
            if len(f) < 8:
                continue
            n_in += 1
            chrom, pos, vid, ref, alt = f[0], f[1], f[2], f[3], f[4]
            if alt in ('.', '') or ref in ('.', ''):
                continue
            info = parse_info(f[7])

            clnsig = norm_sig(info.get('CLNSIG', ''))
            onc = norm_sig(info.get('ONC', '') or info.get('SCI', ''))
            if not clnsig and not onc:
                continue

            stars = STARS.get(info.get('CLNREVSTAT', ''), 0)
            conflicted = 1 if 'conflicting' in clnsig else 0

            origin_bits = 0
            try:
                origin_bits = int(info.get('ORIGIN', '0'))
            except ValueError:
                pass
            origins = []
            if origin_bits & ORIGIN_GERMLINE:
                origins.append('germline')
            if origin_bits & ORIGIN_SOMATIC:
                origins.append('somatic')
            origin = ','.join(origins) if origins else 'unknown'

            gene = info.get('GENEINFO', '')
            symbol, entrez = ('', '')
            if gene:
                first = gene.split('|')[0]
                if ':' in first:
                    symbol, entrez = first.split(':', 1)

            def cuis(key):
                seen, out = set(), []
                for token in re.findall(r'MedGen:(C[N]?\d+)', info.get(key, '')):
                    if token not in seen:
                        seen.add(token)
                        out.append(token)
                return ','.join(out)

            cui, cui_som = cuis('CLNDISDB'), cuis('ONCDISDB')
            trait = info.get('CLNDN', '').replace('|', ',')
            trait_som = info.get('ONCDN', '').replace('|', ',')

            mc = info.get('MC', '')
            consequence = ''
            if mc:
                parts = mc.split(',')[0].split('|')
                consequence = parts[1] if len(parts) > 1 else ''

            nsub, refseq, hgvsc, hgvsp = summ.get(vid, ('', '', '', ''))
            pmids = ','.join(sorted(cites.get(vid, []), key=lambda x: int(x) if x.isdigit() else 0))

            mol_effect = ''
            if consequence:
                mol_effect = '%s:%s:%s:%s' % (consequence, refseq or '.', hgvsc or '.', hgvsp or '.')

            tags = ['CLINVAR_MSID=%s' % vid]
            if info.get('ALLELEID'):
                tags.append('CLINVAR_ALLELE_ID=%s' % info['ALLELEID'])
            if clnsig:
                tags.append('CLINVAR_CLNSIG=%s' % clnsig)
                tags.append('CLINVAR_CLASSIFICATION=%s' % five_tier(clnsig))
            if onc:
                tags.append('CLINVAR_CLNSIG_SOMATIC=%s' % onc)
            tags.append('CLINVAR_REVIEW_STATUS_STARS=%d' % stars)
            tags.append('CLINVAR_CONFLICTED=%d' % conflicted)
            if nsub:
                tags.append('CLINVAR_NUM_SUBMITTERS=%s' % nsub)
            if entrez:
                tags.append('CLINVAR_ENTREZGENE=%s' % entrez)
            tags.append('CLINVAR_VARIANT_ORIGIN=%s' % origin)
            if cui:
                tags.append('CLINVAR_UMLS_CUI=%s' % cui)
            if cui_som:
                tags.append('CLINVAR_UMLS_CUI_SOMATIC=%s' % cui_som)
            if pmids:
                tags.append('CLINVAR_PMID=%s' % pmids)
            if hgvsp:
                tags.append('CLINVAR_HGVSP=%s' % hgvsp)
            if mol_effect:
                tags.append('CLINVAR_MOLECULAR_EFFECT=%s' % mol_effect)

            vout.write('%s\t%s\t.\t%s\t%s\t.\tPASS\t%s\n'
                       % (chrom, pos, ref, alt, ';'.join(tags)))

            cls = five_tier(clnsig) if clnsig else ''
            row = {
                'chrom': chrom, 'pos': pos, 'ref': ref, 'alt': alt,
                'allele_id': info.get('ALLELEID', ''), 'variation_id': vid,
                'rsid': info.get('RS', ''), 'origin_simple': origin,
                'clinical_significance_concensus': clnsig,
                'review_status_concensus': info.get('CLNREVSTAT', ''),
                'num_submitters': nsub, 'no_phenotype': '0' if trait else '1',
                'gold_stars': str(stars), 'conflicted': str(conflicted),
                'pathogenic': '1' if cls == 'Pathogenic' else '0',
                'benign': '1' if cls == 'Benign' else '0',
                'vus': '1' if cls == 'VUS' else '0',
                'somatic': '1' if 'somatic' in origin else '0',
                'class5': '1' if cls == 'Pathogenic' else '0',
                'class4': '1' if cls == 'Likely_Pathogenic' else '0',
                'class3': '1' if cls == 'VUS' else '0',
                'class2': '1' if cls == 'Likely_Benign' else '0',
                'class1': '1' if cls == 'Benign' else '0',
                'classification': cls,
                'variation_type': info.get('CLNVC', ''),
                'truncating_variant': '1' if consequence in
                    ('nonsense', 'frameshift_variant', 'stop_gained') else '0',
                'nontruncating_variant': '0' if consequence in
                    ('nonsense', 'frameshift_variant', 'stop_gained') else '1',
                'refseq_transcript_id': refseq, 'entrezgene': entrez,
                'symbol': symbol, 'molecular_consequence': consequence,
                'hgvs_p': hgvsp, 'hgvs_c': hgvsc, 'hgvs_p_short': hgvsp,
                'molecular_effect': mol_effect,
                'clinical_significance_somatic': onc, 'pmid_somatic': '',
                'cui_somatic': cui_som, 'trait_somatic': trait_som,
                'cui': cui, 'pmid': pmids, 'trait': trait,
                'VAR_ID': '%s_%s_%s_%s' % (chrom, pos, ref, alt),
                'build': a.assembly,
            }
            tout.write('\t'.join(row.get(c, '') for c in TSV_COLS) + '\n')
            n_out += 1

    os.replace(a.out_vcf + '.tmp', a.out_vcf)
    sys.stderr.write('[clinvar] read %d records, wrote %d\n' % (n_in, n_out))


if __name__ == '__main__':
    main()
