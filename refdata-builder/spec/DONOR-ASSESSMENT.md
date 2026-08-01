# Phase 0.3 — PCGR `20260620` as a donor for the gvanno bundle

Assessed 2026-08-01 by extracting both bundles side by side on hephaestus and
diffing every contract in [`README.md`](README.md).

**Verdict: PCGR 2.3 covers 6 of the 8 rebuildable resources**, four of them at
zero or near-zero cost. This removes most of the data engineering originally
scoped for Phase 1 — dbNSFP 5.3 and ClinVar 2026-06 arrive already built,
already GRCh37+GRCh38, and already curated by the upstream author.

PCGR keeps gvanno's directory convention (`data/<asm>/{gene,misc,variant}/…`),
so paths line up without translation.

## Per-resource verdict

| Resource | PCGR 2.3 | Cost | Notes |
|---|---|---|---|
| `misc/tsv/hotspot/hotspot.tsv.gz` | **identical header** | **drop-in** | 13 columns, byte-compatible layout |
| `variant/vcf/gwas/gwas.vcf.gz` | **identical `GWAS_HIT` format** | **drop-in** | `rsid\|risk_allele\|pmid\|tag_snp\|p_value\|efo_id`; 176 KB vs our 108 KB |
| `variant/vcf/dbnsfp/dbnsfp.vcf.gz` | same 6 leading fields, **25 predictors (v5.3)** vs our 18 (v4.5) | **low** — regenerate `vcf_infotags_gvanno.tsv` | see below |
| `variant/vcf/clinvar/clinvar.vcf.gz` | 18 tags vs our 16 | **low** — rename + subset | see below |
| `misc/tsv/protein_domain/protein_domain.tsv.gz` | 5 cols vs our 3 | **low** — project + dedupe | PCGR adds `entrezgene`, `pfam_entry_locations` |
| `variant/tsv/clinvar/clinvar.tsv.gz` | superset with renames | **low** — project + rename | `num_submitters`→`num_submissions`; `nontruncating_variant` dropped |
| `gene/…/gene_transcript_xref.*` | 33 fields, reordered | **medium** — 4 fields have **no donor** | see below |
| `misc/bed/ncer/ncer.bed.gz` | **absent** — PCGR dropped ncER | none | carry forward the 2.69 GB file verbatim; no newer ncER exists anyway |

## dbNSFP — drop-in for the parser, but the output tags must be regenerated

PCGR's header uses the **same six leading fields**
(`refAA|altAA|codonpos|ensembl_gene_id|ensembl_trans_id|proteinpos`), so
`dbnsfp.py`'s self-describing parse works unmodified.

The predictor sets differ substantially:

| | v4.5 (ours, 18) | v5.3 (PCGR, 25) |
|---|---|---|
| **kept** | SIFT · MutationTaster · MutationAssessor · PROVEAN · M-CAP · MutPred · GERP_rs · PrimateAI · DEOGEN2 · LIST_S2 · BayesDEL_addAF · metaRNN · splice_site_ada · splice_site_rf | same |
| **dropped** | LRT · FATHMM · FATHMM_MKL_coding · Aloft | — |
| **new** | — | AlphaMissense · CADD · ClinPred · ESM1b · FATHMM_xf · MutFormer · PHACTboost · PolyPhen2_HVAR · REVEL · VEST4 · BayesDEL_addAF_score |

Consequences for the rebuild:

1. `vcf_infotags_gvanno.tsv` currently declares **17** `DBNSFP_*` output tags.
   It must be regenerated to match the new predictor set, or the new tags are
   undeclared in the output VCF header.
2. `DBNSFP_ALOFTPRED`, `DBNSFP_FATHMM`, `DBNSFP_FATHMM_MKL` and the LRT column
   **will disappear** — the predictors no longer exist upstream. This is real,
   expected output drift and must be called out in the CHANGELOG.
3. The Phase 2 gate's "column set must be identical" rule **cannot hold for
   `DBNSFP_*`**. Amend it: VEP-derived and `NCER_*` columns must not drift;
   `DBNSFP_*` columns are expected to change membership.

## ClinVar — small tag transform

| | gvanno (16) | PCGR (18) |
|---|---|---|
| shared | 15 tags | 15 tags |
| gvanno only | `CLINVAR_REVIEW_STATUS_STARS` | — |
| PCGR only | — | `CLINVAR_GOLD_STARS`, `CLINVAR_CONTRIB_CLNS_GERMLINE`, `CLINVAR_PHENOTYPE_STATUS` |

`CLINVAR_GOLD_STARS` is the same quantity as `CLINVAR_REVIEW_STATUS_STARS`
under a new name (the underlying `clinvar.tsv.gz` calls the column `gold_stars`
in both bundles). Rename it back and drop the two extras — or keep them and
extend the tag file. Renaming is safer: `gvanno_finalize.py` and the 221-column
TSV contract expect the old name.

## Gene/transcript xref — the one real gap

PCGR reordered the tag and **dropped four fields gvanno needs**:

- `cgc_tier`, `cgc_somatic`, `cgc_germline` — Cancer Gene Census
- `mim_phenotype_id` — OMIM

Confirmed absent from `gene_transcript_xref.tsv.gz` and not recoverable from
`gene/tsv/gene_cpg/` (which carries CPG allele-frequency data, not CGC tiers).

PCGR also **adds** `cds_start`, `mane_select2`, `mane_plus_clinical2`, so the
transform is a field remap, not a truncation.

Sourcing the four missing fields:

| Field | Source | Access |
|---|---|---|
| `cgc_*` | COSMIC Cancer Gene Census | free account, non-commercial |
| `mim_phenotype_id` | OMIM `genemap2.txt` | free registration, non-commercial |

Both are gettable, but each needs an account, so this step cannot be fully
automated in CI without stored credentials. It is the critical path of Phase 1.

## Recommended Phase 1 build strategy

1. **Lift wholesale:** `hotspot.tsv.gz`, `gwas.vcf.gz` (+`.tbi`).
2. **Lift + regenerate infotags:** `dbnsfp.vcf.gz` (+`.tbi`), rewriting the
   `DBNSFP_*` block of `vcf_infotags_gvanno.tsv` from the header's `Format:`
   string so the two can never drift.
3. **Lift + transform:** `clinvar.vcf.gz` (tag rename/subset),
   `clinvar.tsv.gz` and `protein_domain.tsv.gz` (column projection).
4. **Carry forward:** `ncer.bed.gz` (+`.tbi`, +tag file) from 20231224.
5. **Build:** `gene_transcript_xref.*` — remap PCGR's 33 fields into gvanno's
   34-field order, then fill `cgc_*` from the Cancer Gene Census and
   `mim_phenotype_id` from OMIM.
6. **Regenerate:** `RELEASE_NOTES`, `gene_transcript_xref_bedmap.tsv.gz`
   (mechanical from the field order).

Both assemblies: PCGR ships grch37 and grch38, so GRCh37 gets the same
treatment with no extra sourcing.

## Licensing note

The PCGR bundle is redistributed under the terms of its constituent databases.
dbNSFP within it remains **CC BY-NC-ND — academic / non-commercial only**.
Biocentric confirms no current commercial activity, so local use and the build
are fine; revisit before any commercial use, and see
[`../../../nf-gvanno-refdata-2026/04-risks-open-questions.md`](../../nf-gvanno-refdata-2026/04-risks-open-questions.md)
on whether to mirror dbNSFP-derived files publicly.
