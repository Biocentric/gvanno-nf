# Usage

## Samplesheet

```csv
sample,vcf,vcf_index
patientA,/data/A.vcf.gz,/data/A.vcf.gz.tbi
patientB,/data/B.vcf.gz,
```

- `sample` — unique ID, used to name outputs. Must match `[A-Za-z0-9._-]+`.
- `vcf` — path to a single-sample germline VCF (≥ v4.2).
- `vcf_index` — optional. If blank, the pipeline looks for `<vcf>.tbi` next to the VCF.

## Reference data (one-off setup)

The pinned gvanno bundle is ~20 GB across four sources. Stage it once:

```bash
nextflow run Biocentric/gvanno-nf -profile docker \
    -entry PREPARE_REFERENCES \
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
| `--vep_lof_prediction` | `--vep_lof_prediction` | false |
| `--vep_no_intergenic` | `--vep_no_intergenic` | false |
| `--vep_coding_only` | `--vep_coding_only` | false |
| `--vcfanno_n_processes` | `--vcfanno_n_processes` | 4 |
| `--oncogenicity_annotation` | `--oncogenicity_annotation` | false (requires `--vep_lof_prediction`) |

## Performance knobs (new vs. upstream)

| Param | Effect |
|---|---|
| `--scatter_by chromosome` | Split per-contig and run VEP/vcfanno in parallel; gathered with `bcftools concat` before the TSV step. Default `none`. |
| `--max_cpus` / `--max_memory` / `--max_time` | Caps applied to all process labels. |
| `-profile slurm,awsbatch,...` | Standard Nextflow executor profiles. |

## What you don't need anymore

`--container`, `--force_overwrite`, `--debug`, `--docker_uid`, `--gvanno_dir`, `--sif_file` from upstream gvanno are all subsumed by Nextflow's profile/resume/container machinery.
