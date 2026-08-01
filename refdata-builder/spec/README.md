# Bundle format spec — captured from `gvanno.databundle.grch38.20231224.tgz`

Everything here was extracted from the upstream 20231224 bundle on 2026-08-01.
It is the **build target**: a rebuilt bundle must reproduce these paths, INFO
tag names and column layouts, or the `sigven/gvanno:1.7.0` helpers will either
fail or — worse — silently drop annotations.

Captured with `refdata-builder/steps/capture-spec.sh` against
`/mnt/big/gvanno-build/ref-20231224/data/grch38`.

## Version manifest of the bundle we are replacing

From `RELEASE_NOTES` (this file is a plain `key = value` list; the two leading
`##` lines are read by the helpers):

```
##GVANNO_SOFTWARE_VERSION = 1.7.0
##GVANNO_DB_VERSION = 20231224
pfam = v36.0
ncER = v1.0 (March 2019)
uniprot = release 2023_05
cancerhotspots = v2 (2017)
dbsnp = build 154
dbnsfp = v4.5 (November 2023)
gnomad = r2.1 (October 2018)
gwas = November 2023 (20231123)
clinvar = December 2023 (20231203)
gencode = 44/19
```

## Full file inventory (grch38, excluding `.vep/`)

| Path | Size | Rebuild? |
|---|---|---|
| `RELEASE_NOTES` | 316 B | yes — version manifest |
| `vcf_infotags_gvanno.tsv` | — | yes — defines gvanno INFO tags |
| `vcf_infotags_vep.tsv` | — | yes — defines VEP CSQ tags |
| `variant/vcf/clinvar/clinvar.vcf.gz` (+tbi) | 84 MB | **yes** |
| `variant/vcf/clinvar/clinvar.vcfanno.vcf_info_tags.txt` | 1.8 KB | yes — 16 tags |
| `variant/tsv/clinvar/clinvar.tsv.gz` | 107 MB | **yes** — trait resolution in `gvanno_finalize.py` |
| `variant/vcf/dbnsfp/dbnsfp.vcf.gz` (+tbi) | 1.1 GB | **yes** |
| `variant/vcf/dbnsfp/dbnsfp.vcfanno.vcf_info_tags.txt` | 537 B | yes — single `DBNSFP` tag |
| `variant/vcf/gwas/gwas.vcf.gz` (+tbi) | — | **yes** |
| `variant/vcf/gwas/gwas.vcfanno.vcf_info_tags.txt` | 183 B | yes — single `GWAS_HIT` tag |
| `gene/bed/gene_transcript_xref/gene_transcript_xref.bed.gz` (+tbi) | 6.7 MB | **yes** |
| `gene/bed/gene_transcript_xref/gene_transcript_xref_pc_nopad.bed.gz` (+tbi) | 1.7 MB | **yes** |
| `gene/bed/gene_transcript_xref/gene_transcript_xref.vcfanno.vcf_info_tags.txt` | 911 B | yes — 34-field tag |
| `gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz` | 12 MB | **yes** — the actual xref table |
| `gene/tsv/gene_transcript_xref/gene_transcript_xref_bedmap.tsv.gz` | 320 B | yes — trivial 35-line index→name map |
| `misc/bed/ncer/ncer.bed.gz` (+tbi) | **2.69 GB** | no — carry forward verbatim |
| `misc/bed/ncer/ncer.vcfanno.vcf_info_tags.txt` | 182 B | carry forward |
| `misc/tsv/hotspot/hotspot.tsv.gz` | 82 KB | **yes** — 3,532 rows |
| `misc/tsv/hotspot/hotspot_long.tsv.gz` | 121 KB | **yes** |
| `misc/tsv/protein_domain/protein_domain.tsv.gz` | 405 KB | **yes** — Pfam v36.0 |

Note the tarball also contains macOS AppleDouble `._*` sidecars throughout —
the upstream bundle was tarred on a Mac. They are inert; do not reproduce them.

## The `DBNSFP` tag contract — self-describing, not hardcoded

**This is the single most important finding, and it reverses the assumption the
project plan was written on.**

`lib/gvanno/dbnsfp.py` does **not** hardcode a list of prediction algorithms.
It parses them at runtime from the `DBNSFP` INFO header's `Format:` string,
taking every `|`-separated subtag from **index 6 onward** and stripping any
`_score` / `_pred` suffix:

```python
if identifier == 'DBNSFP':
    i = 6
    while (i < len(subtags)):
        dbnsfp_prediction_algorithms.append(
            str(re.sub(r'((_score)|(_pred))"*$', '', subtags[i])))
        i = i + 1
```

What is actually enforced, in `map_dbnsfp_predictions()`:

```python
if len(algorithms) != len(dbnsfp_info[6:]):
    return effect_predictions      # <-- silently returns EMPTY
```

So the contract is **header ↔ data agreement**, both of which we control:

- Fields `0–5` are fixed in meaning:
  `refAA | altAA | codonpos | ensembl_gene_id | ensembl_trans_id | proteinpos`.
  The code reads `[0]`=ref_aa, `[1]`=alt_aa, `[3]`=gene IDs (`&`-split),
  `[5]`=AA positions (`&`-split). `[2]` and `[4]` are carried but unused here.
- Fields `6..N` are whatever the header declares. **Adding or removing
  predictors is legal** as long as every data record carries the same count.

The 20231224 bundle declares **18 algorithms** → 24 fields total. Verified
against the first data record: 24 fields. Declared order:

```
SIFT · LRT · Mutationtaster · MutationAssessor · FATHMM · FATHMM_MKL_coding
PROVEAN · M-CAP · MutPred · GERP_rs · PrimateAI · DEOGEN2 · LIST_S2
BayesDEL_addAF · Aloft · metaRNN · splice_site_ada · splice_site_rf
```

⚠️ **The failure mode is silent.** A count mismatch does not raise — it returns
no predictions at all, and the pipeline completes successfully with empty
`EFFECT_PREDICTIONS` and `DBNSFP_*` columns. A smoke test will not catch it.
`verify/check_bundle.py` must assert the count explicitly, and the Phase 2
validation gate must assert that `EFFECT_PREDICTIONS` is non-empty for a known
missense variant.

## `GENE_TRANSCRIPT_XREF` — 34 pipe-separated fields

Field order is fixed and mirrored in `gene_transcript_xref_bedmap.tsv.gz`
(a 35-line `index → name` map, header + 34 rows):

```
0  ENSEMBL_TRANSCRIPT_ID     12 ACTIONABLE_GENE     23 CGC_GERMLINE
1  ENSEMBL_GENE_ID           13 TSG                 24 INTOGEN_ROLE
2  ENSEMBL_PROTEIN_ID        14 TSG_SUPPORT         25 TCGA_DRIVER
3  SYMBOL                    15 TSG_RANK            26 NCG_DRIVER
4  ENTREZGENE                16 ONCOGENE            27 CPG_SOURCE
5  UNIPROT_ID                17 ONCOGENE_SUPPORT    28 CPG_CANCER_CUI
6  UNIPROT_ACC               18 ONCOGENE_RANK       29 CPG_SYNDROME_CUI
7  REFSEQ_TRANSCRIPT_ID      19 DRIVER              30 CPG_MOI
8  REFSEQ_PROTEIN_ID         20 DRIVER_SUPPORT      31 CPG_MOD
9  PRINCIPAL_ISOFORM_FLAG    21 CGC_TIER            32 GE_PANEL_ID
10 GENCODE_TAG               22 CGC_SOMATIC         33 MIM_PHENOTYPE_ID
11 GENCODE_TRANSCRIPT_BIOTYPE
```

Because the bedmap is generated from this same order, it is regenerable — it is
**not** a curated data file. The curated content lives in
`gene_transcript_xref.tsv.gz` and the two BEDs.

Upstream sources implied by these columns are broader than the project plan
listed: Ensembl, UniProt, RefSeq, APPRIS, GENCODE, **Cancer Gene Census**,
**IntOGen**, **TCGA driver (Bailey 2018)**, **Network of Cancer Genes**,
CancerMine, **Genomics England PanelApp**, and **OMIM/MedGen**.

## Other tag contracts

| Resource | Tag | Shape |
|---|---|---|
| ClinVar | 16 separate `CLINVAR_*` tags | see `vcfanno_tags/clinvar.vcfanno.vcf_info_tags.txt` |
| GWAS | single `GWAS_HIT` | `rsid\|risk_allele\|pmid\|tag_snp\|p_value\|efo_id` |
| ncER | single `NCER_PERCENTILE` | 10 bp resolution genome-wide percentile |

## `hotspot.tsv.gz` columns

```
symbol · entrezgene · amino_acid_position · reference_amino_acid · vartype
qvalue · codon · hgvsc · hgvsp · hgvsp2 · MUTATION_HOTSPOT
MUTATION_HOTSPOT2 · MUTATION_HOTSPOT_CANCERTYPE
```

3,532 rows. `MUTATION_HOTSPOT` packs `symbol|entrezgene|codon|alt_aa|qvalue`;
`MUTATION_HOTSPOT_CANCERTYPE` packs `cancertype|n|n` entries joined by `,`.
