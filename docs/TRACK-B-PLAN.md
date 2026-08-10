# Track B (v0.3.0) — rebuild the container on Ensembl VEP 115

Researched 2026-08-01/09 across six dimensions, with blocker- and high-impact
claims independently challenged. Facts marked **[V]** were verified against a
primary source; where a refutation overturned a research finding, that is
stated inline.

---

## 1. Bottom line

**Track B is feasible as scoped. VEP 115 is the right target and nothing found
forces a different one.** Two things change the shape of the work versus what
the v0.2.0 planning assumed:

- **LOFTEE is not the blocker it looked like.** The VEP plugin interface is
  byte-identical from 110 through 116 (`BaseVepPlugin.pm` is 11,774 bytes in
  every release; the only diff is a copyright year), every Bio::EnsEMBL method
  LOFTEE calls is unchanged, and nf-core/sarek pins `vep_version = "115.2-1"`
  and runs `--plugin LoF` in production. **[V]** Every "LOFTEE broke on modern
  VEP" report traced to a missing Perl dep, not a version regression — and the
  chosen base image already has all five (`Bio::Perl`, `Bio::DB::HTS`,
  `Bio::DB::BigWig`, `DBD::SQLite`, `List::MoreUtils`). **[V]**
- **A new blocker appeared that nobody was looking for: a gnomAD CSQ field
  rename that landed in VEP 113.** `gnomADe_OTH_AF` → `gnomADe_REMAINING_AF`,
  `gnomADg_OTH_AF` → `gnomADg_REMAINING_AF`, plus a new `gnomADe_MID_AF`. **[V]**
  The bundle's `vcf_infotags_vep.tsv` still declares the `OTH` names, so two
  declared columns silently empty and two undeclared ones appear. This is
  exactly the Track A failure class.

## 2. Decisions

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D1 | Build VEP from source vs. layer on the official image | **Layer on `ensemblorg/ensembl-vep:release_115.2`** | 258 MB vs 1.5 GB, Ubuntu 22.04.5, VEP 115.2, and it already has `/opt/vep/src/ensembl-vep/modules` — the exact path `get_loftee_dir()` hardcodes. **[V]** Deletes the entire from-source VEP build. |
| D2 | Patch the gvanno helpers vs. adapt the bundle | **Vendor and patch** | Not a preference — adapting is *impossible*. `VEP_VERSION='110'` drives both `--cache_version` **and** the on-disk cache paths for the FASTA and the LOFTEE ancestral FASTA. **[V]** No bundle layout can satisfy both. |
| D3 | Keep or drop LOFTEE | **Keep** | It works (see §1). Dropping costs 4 CSQ subfields, the `LOSS_OF_FUNCTION` flag, and evidence code `CLINGEN_VICC_OVS1` — which carries weight **+8**, the single largest positive weight in the oncogenicity classifier. |
| D4 | Docker Hub vs GHCR | **GHCR**, `ghcr.io/biocentric/gvanno-nf:2026.1` | The project already authenticates to GitHub. Needs `write:packages` added to the token — the current one has `gist, read:org, repo` only. |
| D5 | Python version | **3.11 or 3.12, and pin pandas < 3.0** | See R2. Do not take pandas 3 in the same change as VEP 115. |

## 3. The container

Base image inventory, verified by running it:

| | |
|---|---|
| present | `vep` 115.2, `bgzip`, `tabix`, `xxd`, `egrep`, `perl` 5.34, all five LOFTEE Perl deps, `/opt/vep/src/ensembl-vep/modules`, 75 plugins in `/plugins` |
| **absent** | **`python3`** (`python` → python2, no `pip3`), `samtools`, `bcftools`, `vt`, `vcfanno`, `vcf2tsvpy`, `NearestExonJB.pm` in `modules/`, `LoF.pm` |

> The missing-Python finding was marked "refuted" during verification, but that
> refutation attacked a **misquoted** claim — it checked whether *sigven/gvanno*
> has Python 3 (it does) rather than the *ensemblorg* base (it does not).
> Settled by direct inspection: `python3: command not found`. **[V]**

> Similarly, the research claimed the base image "already ships
> `NearestExonJB.pm`". It ships it in **`/plugins`**, not in `modules/` where
> gvanno's `--dir_plugins` points. It must be copied across. **[V]**

Dockerfile shape:

```dockerfile
FROM ensemblorg/ensembl-vep:release_115.2
USER root
# 1. Python 3 + the gvanno helper stack (absent from the base entirely)
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-dev samtools bcftools \
    && ln -sf /usr/bin/python3 /usr/local/bin/python && rm -rf /var/lib/apt/lists/*
RUN pip3 install --no-cache-dir 'pandas<3.0' numpy scipy cyvcf2 vcf2tsvpy
# 2. vcfanno + vt (single static binary / small build)
# 3. plugins into the dir gvanno hardcodes, NOT /plugins
COPY NearestExonJB.pm  /opt/vep/src/ensembl-vep/modules/     # from release/115
ADD  loftee_1.0.3.tgz  /opt/vep/src/ensembl-vep/modules/     # konradjk grch38 @8c111b7
# 4. vendored + patched gvanno helpers
COPY gvanno/ /gvanno/
```

**Do not** carry `UTRannotator.tgz` over. It is `ADD`ed by the upstream
Dockerfile and referenced by **nothing** — no gvanno Python module mentions it,
and `gvanno_vep.py`'s plugin list is only `NearestExonJB` and `LoF`. **[V]**

`gvanno_vars.py` patches — mandatory, all three:

```python
VEP_VERSION     = '115'          # drives --cache_version AND the cache paths
GENCODE_VERSION = {'grch38': 49, 'grch37': 19}
DB_VERSION      = '<new bundle version>'
```

## 4. The VEP cache and what it buys

Release 115 (Sep 2025) contents, **[V]**:

| | GRCh38 | GRCh37 |
|---|---|---|
| GENCODE | **49** | **19** (unchanged from 110) |
| dbSNP | 156 | 156 |
| gnomAD exomes | v4.1 | v4.1 |
| gnomAD genomes | v4.1 | **none in Ensembl variation data** |
| COSMIC | 101 | 98 |
| ClinVar (in cache) | 2025-02 | 2023-06 |
| MANE | v1.4 | n/a |

Three consequences that must be handled explicitly:

- **`--af_gnomad` yields exomes only.** It survives in 115 as a back-compat
  alias of `--af_gnomade`. To get genome frequencies the rebuilt
  `gvanno_vep.py` must also pass **`--af_gnomadg`** — GRCh38 only. **[V]**
  The bundle already declares 11 `gnomADg_*` tags that have **never been
  populated** in any release, because that flag was never passed. **[V]**
- **The gnomAD win is capped by dbSNP accessioning.** The cache only carries
  frequencies for variants dbSNP has accessioned, and 115 is on b156. gnomAD
  v4.1 postdates it, so the realised fill-rate gain will be smaller than the
  5.8× raw sample-size increase suggests. **Measure it; do not assume it.**
- **The bare `MANE` CSQ field is now populated** (`MANE_Select` /
  `MANE_Plus_Clinical`) where in 110 it existed but was never assigned. **[V]**
  A new non-empty column.

## 5. The bundle

Most of `20260801` carries over. What must be rebuilt against Ensembl 115:

| Component | Action |
|---|---|
| `vcf_infotags_vep.tsv` | **Rewrite the gnomAD block**: drop `*_OTH_AF`, add `*_REMAINING_AF` and `gnomADe_MID_AF`. Highest-priority change in the whole bundle. |
| `gene_transcript_xref` | Rebuild on GENCODE 49 — already done for `20260801`, so likely carries over. Verify against the 115 transcript set. |
| LOFTEE ancestral FASTA | **Relocate** to `<cache>/homo_sapiens/115_GRCh3x/human_ancestor.fa.gz` (+`.fai`, +`.gzi`). The path is version-derived. **[V]** |
| ClinVar, dbNSFP, hotspots, GWAS, Pfam, ncER, CGC, MIM | Unchanged — position- or gene-keyed, independent of VEP version |

`refdata-builder/` is already assembly-parameterised; it needs an
**Ensembl-version** parameter threaded through `assemble-bundle.sh` (for
`RELEASE_NOTES`) and `build-gene-xref.sh`.

## 6. The validation gate, redefined

The Track A rule — zero drift in VEP-derived columns — is invalid here, and the
join key itself breaks: rows are matched on `Feature`, which is exactly what
GENCODE 44→49 changes. GENCODE goes 252,835 → 507,365 transcripts (+100.7%)
and 62,700 → 78,691 genes (+25.5%). **[V]**

The replacement rests on a structural gift:

> **GRCh37's VEP 115 cache is still GENCODE 19 — identical to 110.** So the
> 8,871-variant GRCh37 example VCF has essentially *no* legitimate transcript
> churn and can keep near-strict transcript invariants. **GRCh37 becomes the
> control arm that proves the container rebuild did not break VEP**, while
> GRCh38 measures the intended gain. **[V]**

| Tier | Columns | Rule |
|---|---|---|
| **Strict** | `CLINVAR_*`, `NCER_PERCENTILE`, `GWAS_HIT` | Bundle-carried and position-keyed; the bundle is identical on both sides. **Zero differences.** Any movement proves the VEP swap corrupted vcfanno's input. |
| **Strict on GRCh37 only** | `Feature`, `SYMBOL`, `HGVSp_short`, `CONSEQUENCE` | GENCODE 19 both sides → near-zero churn expected |
| **Directional on GRCh38** | `gnomADe_AF` fill rate, `DBSNPRSID` hit rate | Must **increase**. A decrease is a failure. |
| **Bounded** | row count, MANE-anchored `Feature` churn | Rows may grow (GENCODE 49 adds ~16k mostly-lncRNA genes); MANE-anchored churn should be low single digits |

Match rows on **variant + gene** rather than variant + transcript, so the key
survives a transcript-set change.

New value-grammar assertions — the class of check that would have caught both
Track A bugs:

- every `CLINVAR_CLNSIG` value matches a plain-token grammar, never `CUI:sig:count`
- `EFFECT_PREDICTIONS` non-empty on a known missense variant
- **no declared CSQ column is 100% empty** — this alone catches the
  `OTH`→`REMAINING` rename, the `--af_gnomadg` omission, and a silently
  failing plugin
- `check_bundle.py` must stop sampling only file heads (currently n=200/2000)

## 7. Phased plan

| Phase | Work | Effort |
|---|---|---|
| B0 | Vendor `sigven/gvanno` `src/gvanno/` at a pinned commit into the repo; patch `gvanno_vars.py`; add `--af_gnomadg`; guard the unguarded xref lookups | 2–3 d |
| B1 | Build + publish `ghcr.io/biocentric/gvanno-nf:2026.1` | 2–3 d |
| B2 | Stage the VEP 115 caches (26 GB GRCh38 / 23 GB GRCh37) + relocate the LOFTEE ancestor | 1 d, mostly download |
| B3 | Rewrite the gnomAD block of `vcf_infotags_vep.tsv`; rebuild the bundle as `2026xxxx` | 2–3 d |
| B4 | Redefine the gate per §6; run GRCh37 control arm, then GRCh38 | 3–4 d |
| B5 | Measure the actual gnomAD/dbSNP fill-rate gain; ship or reconsider | 1–2 d |

**B5 is a real decision point**, not a formality. If the dbSNP-accessioning cap
means gnomAD fill barely moves, Track B's headline benefit evaporates and the
container churn may not be worth it on its own.

## 8. Risks

| | Risk | Impact | Survived scrutiny? | Mitigation |
|---|---|---|---|---|
| R1 | gnomAD `OTH`→`REMAINING` rename silently empties columns | High | **Yes, [V]** | Rewrite the tag spec; add the "no declared column 100% empty" assertion |
| R2 | **pandas 3.0 raises** in `variant.py:170-186` — verified by execution: `TypeError: Invalid value '-1' for dtype 'str'` | High | **Yes, [V] by running it** | Pin `pandas<3.0`. Do not combine a pandas major with a VEP major. |
| R3 | `utils.check_subprocess()` **exits 0 on failure** — every external call, including `vep` itself, can fail silently | High | **Yes, [V]** | Patch it to propagate the exit code. This is why a broken plugin would go unnoticed. |
| R4 | gnomAD gain capped by dbSNP b156 accessioning | High | **Yes, [V]** | Measure in B5 before declaring success |
| R5 | Unguarded `transcript_xref_map[...]['SYMBOL']` in `vep.py:84-86` crashes on GENCODE 49 novel loci | Medium | **Yes, [V]** | Guard the lookup in B0 |
| R6 | `--vep_lof_prediction` is **dead code** — `--plugin LoF` is appended unconditionally and gvanno never passes `--safe`, so a LOFTEE that fails to load only warns to stderr | Medium | **Yes, [V]** | Assert the CSQ header contains `LoF` after the VEP step |
| R7 | LOFTEE incompatible with VEP 115 | — | **Refuted** | Plugin API byte-identical 110→116; sarek runs it on 115.2 |
| R8 | LOFTEE absent from VEP_plugins is an Ensembl decision against it | — | **Refuted** | LOFTEE was *never* in VEP_plugins — third-party at konradjk/loftee, and 115's `plugin_config.txt` still lists it |

## 9. Out of scope

- VEP 116 / GENCODE 50 — revisit when dbNSFP ships a GENCODE 50 build
- Surfacing dbNSFP v5.3's new predictors as their own columns (needs
  `algo_mapping` extended in the vendored helpers — possible now that we
  vendor them, but a separate change)
- Replacing the gvanno helpers with native Nextflow modules
- T2T-CHM13
