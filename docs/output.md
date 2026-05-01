# Output

```
results/
├── pipeline_info/
│   ├── execution_timeline_*.html
│   ├── execution_report_*.html
│   ├── execution_trace_*.txt
│   └── pipeline_dag_*.html
├── prepare_references/                # only after PREPARE_REFERENCES
│   └── verify.log
└── annotation/
    └── <sample>/
        ├── <sample>.gvanno.<assembly>.vcf.gz(.tbi)        # all variants, annotated
        ├── <sample>.gvanno.<assembly>.pass.tsv.gz         # PASS variants, finalised TSV
        └── logs/
            ├── *.vep.log
            └── *.vcfanno.log
```

`<assembly>` is `GRCh37` or `GRCh38` (matches `--genome`).

## File contents

| File | What it is |
|---|---|
| `*.vcf.gz` | The full annotated VCF after VEP + vcfanno + summarise. INFO field carries CSQ, ClinVar, dbNSFP, gnomAD, GWAS, ncER tags. |
| `*.pass.tsv.gz` | One row per (variant × consequence). Columns include sample ID, position, ref/alt, gene, consequence, ClinVar significance + traits, gnomAD AF, dbNSFP scores, optionally LOFTEE LoF call and an oncogenicity classification. Identical column set to upstream gvanno's `*.pass.tsv.gz`. |

## Differences vs. upstream gvanno output

- File naming: `<sample>.gvanno.GRCh38.pass.tsv.gz` (nf-core convention) instead of `<sample>_gvanno_grch38.pass.tsv.gz`.
- We don't currently emit the separate "all variants" TSV by default — only the PASS-only finalised TSV. Set `--keep_intermediates` to get the full intermediate outputs (validate / VEP / vcfanno / summarise / vcf2tsv) under `logs/`.
- Pipeline reports (`execution_*.html`) are nf-core extras; they're not produced by upstream gvanno.
