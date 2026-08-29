# Usage

## Samplesheet

```csv
sample,vcf,vcf_index
patientA,/data/A.vcf.gz,/data/A.vcf.gz.tbi
patientB,/data/B.vcf.gz,
```

- `sample` — unique ID, used to name outputs. Must match `[A-Za-z0-9._-]+`.
- `vcf` — path to a single-sample germline VCF (≥ v4.2).
- `vcf_index` — optional and ignored. `VALIDATE_VCF` re-normalises and re-indexes every input, so a pre-existing index is never used; plain uncompressed `.vcf` inputs are fine.

## Container registry login (v0.3.0 only)

v0.3.0 uses a private GHCR image, so authenticate once per machine before the
first run:

```bash
echo $GHCR_TOKEN | docker login ghcr.io -u Biocentric --password-stdin
```

Without it Nextflow fails on the first process with a pull error. v0.2.0 needs
no login — it uses the public `sigven/gvanno:1.7.0`. Rationale in the README.

## Reference data (one-off setup)

The pinned gvanno bundle is ~20 GB across four sources. Stage it once:

```bash
nextflow run Biocentric/gvanno-nf -profile docker \
    --step prepare_references \
    --genome GRCh38 \
    --refdata_dir /scratch/refs/gvanno \
    --refdata_mode download
```

The pipeline tries each URL in `--refdata_url_base` (default: upstream Oslo mirror, then the GitHub-Releases fallback on this repo). To force a specific mirror:

```bash
--refdata_url_base "['https://my.mirror.org/gvanno']"
```

The bundle layout under `--refdata_dir` matches upstream gvanno verbatim, so the same directory works for both this pipeline and the original gvanno.

## Annotation run

```bash
nextflow run Biocentric/gvanno-nf -profile docker \
    --input samplesheet.csv \
    --genome GRCh38 \
    --refdata_dir /scratch/refs/gvanno \
    --outdir results
```

`-resume` works as expected: re-running with the same samplesheet skips finished samples.

## Tunables (mirror of upstream gvanno's CLI flags)

| Pipeline param | Upstream flag | Default |
|---|---|---|
| `--vep_n_forks` | `--vep_n_forks` | 4 |
| `--vep_buffer_size` | `--vep_buffer_size` | 500 |
| `--vep_pick_order` | `--vep_pick_order` | mane_select,mane_plus_clinical,canonical,appris,tsl,biotype,ccds,rank,length |
| `--vep_regulatory` | `--vep_regulatory` | false |
| `--vep_gencode_basic` | `--vep_gencode_basic` | false |
| `--vep_lof_prediction` | `--vep_lof_prediction` | false — **no effect, see below** |
| `--vep_no_intergenic` | `--vep_no_intergenic` | false |
| `--vep_coding_only` | `--vep_coding_only` | false |
| `--vcfanno_n_processes` | `--vcfanno_n_processes` | 4 |
| `--oncogenicity_annotation` | `--oncogenicity_annotation` | false |

### `--vep_lof_prediction` does nothing — LOFTEE always runs

Verified against upstream `gvanno_vep.py` at the pinned commit and confirmed by
running the pipeline with the flag at its default (`false`):

```
LoF 227 rows · LoF_filter 18 · LoF_flags 4 · LOSS_OF_FUNCTION 1250
```

`--plugin LoF,...` is appended **unconditionally** at `gvanno_vep.py:93`. The
flag's only three occurrences are an argparse declaration, a config assignment,
and a log line that prints "ON"/"OFF" — no other module references it. So:

- LOFTEE runs on every job, and you pay its runtime cost whether or not you ask
  for it.
- `LoF`, `LoF_filter`, `LoF_flags`, `LoF_info` and `LOSS_OF_FUNCTION` are always
  populated.
- `--oncogenicity_annotation` has no real dependency on it; the LoF data it
  needs is always present. The "requires" note previously in this table was
  wrong.

The parameter is kept only for CLI compatibility with upstream `gvanno.py`.
This is upstream behaviour, not something this pipeline introduces.

## Performance knobs (new vs. upstream)

| Param | Effect |
|---|---|
| `--scatter_by chromosome` | Split per-contig and run VEP/vcfanno in parallel; gathered with `bcftools concat` before the TSV step. Default `none`. |
| `--max_cpus` / `--max_memory` / `--max_time` | Caps applied to all process labels. |
| `-profile slurm,awsbatch,...` | Standard Nextflow executor profiles. |

## What you don't need anymore

`--container`, `--force_overwrite`, `--debug`, `--docker_uid`, `--gvanno_dir`, `--sif_file` from upstream gvanno are all subsumed by Nextflow's profile/resume/container machinery.
