# Verification state

Kept honest and current. If something here is stale, that is a bug.

Last updated: **2026-08-01**, bundle `20260801`, container `sigven/gvanno:1.7.0`.

---

## Verified

### Pipeline gates — both assemblies pass

Run on hephaestus (Nextflow 26.04.3 / Docker), comparing bundle `20260801`
against `20231224` on identical input with the same VEP 110 cache. Rows joined
on `(CHROM, POS, REF, ALT, Feature)` by
[`refdata-builder/verify/compare_runs.sh`](../refdata-builder/verify/compare_runs.sh).

| | GRCh38 | GRCh37 |
|---|---|---|
| input | 11-variant fixture | upstream example VCF, 8871 variants |
| shape | 189 cols × 11 rows | 221 cols × 8871 rows |
| rows lost / gained | 0 / 0 | 1 / 0 (explained below) |
| drift in VEP-derived + `NCER_PERCENTILE` | **zero** | **zero** |
| `EFFECT_PREDICTIONS` canary | populated | populated |
| `CLINVAR_CLNSIG` grammar | plain | plain |
| verdict | **PASSED** | **PASSED** |

The one GRCh37 row difference is `21:16031396 T>C / ENST00000400562`. The
baseline emitted **two** rows there, identical except that one carried
`GENENAME` and the other did not — a duplicate gene-xref entry in the
`20231224` bundle. Emitting one row is the correct behaviour.

### 1,250-variant validation panel

250 variants in each ClinVar tier, one per gene, all 24 chromosomes, sampled
from the prior bundle so every one is known to have been annotatable before.
**Zero received the wrong ClinVar ID.** 1245/1250 matched; the five misses were
each traced to ClinVar having retired the record upstream — absent from the
NCBI `20260728` source by ID *and* by locus. Full result in
[`refdata-builder/spec/PANEL-RESULTS.md`](../refdata-builder/spec/PANEL-RESULTS.md).

### Bundle contracts

`check_bundle.py`: **18 checks, 0 failed** on both assemblies. Manifests
(26 entries each) self-check with `sha256sum -c`. Both tarballs checksummed.

### Mirror

<https://github.com/Biocentric/gvanno-nf/releases/tag/refdata-20260801> — 10
assets. Verified the way `BUNDLE_FETCH` consumes it: `parts.txt` manifests
fetch and list three chunks each, all six chunk URLs return 200, and the direct
unchunked URL returns 404 so the fallback path is actually reached.

---

## Not verified

### ~~`--refdata_mode download`~~ — VERIFIED 2026-08-10

Ran end to end on hephaestus against the live mirror, GRCh38, fresh empty
`--refdata_dir`, nothing pre-staged. 3/3 processes, exit 0.

```
[fetch] trying .../gvanno.databundle.grch38.20260801.tgz          -> 404
[fetch] trying chunked .../gvanno.databundle.grch38.20260801.tgz.parts.txt
[fetch] manifest found, reassembling chunks
[fetch] ok (chunked)

[verify] checking sha256 against 26 entries
         26 files OK
```

Three things that had never run together all held:

- **Chunk reassembly** — the direct URL 404s by design, `BUNDLE_FETCH` falls
  through to `.parts.txt` and stitches three ~1.9 GB chunks back together.
- **Checksum verification on a downloaded tree** — every prior verification was
  against a locally built bundle whose files were correct by construction. This
  proves the split → upload → reassemble round trip is byte-exact.
- **The assembly filter** — the manifest holds 52 entries across both
  assemblies; only the 26 for GRCh38 were checked, rather than failing on the
  absent GRCh37 files.

Not yet run for GRCh37, though it shares every code path.

### `check_bundle.py` validates structure, not value grammar

It checks paths, tag names, field counts and indexes. It does **not** check
that values look right. This is not theoretical: the first GRCh37 package
silently shipped PCGR's ClinVar, whose `CLINVAR_CLNSIG` uses a
`CUI:significance:count` encoding gvanno cannot parse, and `check_bundle.py`
passed it 18/18. The gate now has a grammar canary, but the *build-time* check
still doesn't. Sampling records per tag and asserting shape would close it.

### `--scatter_by chromosome`

Still never exercised end-to-end, on either assembly. It was rewritten in
v0.1.0dev to enumerate contigs from the VCF's own tabix index and has not been
run since.

### GRCh37 gene xref — structurally verified only

34 fields, CGC and MIM injected, 196,483 BED records matching the prior bundle
exactly (GRCh37 is frozen at GENCODE 19). But the GRCh37 gate input is the
upstream example VCF, which is not chosen to exercise cancer-gene columns —
`CGC_TIER`, `TSG`, `ONCOGENE` and `MIM_PHENOTYPE_ID` coverage on GRCh37 has not
been checked against a panel the way GRCh38's ClinVar was.

### Bit-identical comparison against upstream `gvanno.py`

Permanently retired. There is no upstream to be identical to — gvanno froze at
v1.7.0 (2023-12-29) and publishes no bundle newer than `20231224`. The
structural gates above replace it. `--refdata_version 20231224` still selects
the old bundle if you need to reproduce a historical run.

### Track B — VEP 115

Not started. VEP stays at 110, so GENCODE (v44/v19), gnomAD (r2.1) and dbSNP
(b154) are unchanged in this release. See the plan in
`X:\claude\nf-gvanno-refdata-2026\`.

### Housekeeping

- `nf-test` coverage: none.
- CI: none.
- `MULTIQC` and `BCFTOOLS_CONCAT` config selectors still match no process —
  Nextflow logs a benign `WARN` for each.
- Literal `<NA>` strings appear in `ENTREZGENE` (118 rows of 8871 on GRCh37).
  A pandas artefact from the container's own summarise/finalize, present in
  the `20231224` output too (122 rows) and slightly reduced. Container-side,
  not fixable from the bundle.
