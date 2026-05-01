# Citations

## Cite gvanno first

This pipeline is a Nextflow re-orchestration of [**sigven/gvanno**](https://github.com/sigven/gvanno). The science, the helper scripts, the Docker image, and the curated annotation bundle are entirely the work of the upstream gvanno project. Please cite gvanno when you use `Biocentric/gvanno-nf`:

> **gvanno: generic workflow for functional and clinical annotation of human DNA variants.**
> Sigve Nakken et al. https://github.com/sigven/gvanno

Contact: `sigven AT ifi.uio.no`.

## Cite the underlying tools

`gvanno-nf` is a thin layer on top of these tools — please cite them too where relevant.

### Workflow / orchestration

- **Nextflow**
  Di Tommaso, P., Chatzou, M., Floden, E. W., Barja, P. P., Palumbo, E., & Notredame, C. (2017). *Nextflow enables reproducible computational workflows.* Nature Biotechnology, 35(4), 316–319. https://doi.org/10.1038/nbt.3820

- **nf-core**
  Ewels, P. A., Peltzer, A., Fillinger, S., Patel, H., Alneberg, J., Wilm, A., Garcia, M. U., Di Tommaso, P., & Nahnsen, S. (2020). *The nf-core framework for community-curated bioinformatics pipelines.* Nature Biotechnology, 38(3), 276–278. https://doi.org/10.1038/s41587-020-0439-x

### Variant annotation

- **Ensembl Variant Effect Predictor (VEP)**
  McLaren, W., Gil, L., Hunt, S. E., Riat, H. S., Ritchie, G. R. S., Thormann, A., Flicek, P., & Cunningham, F. (2016). *The Ensembl Variant Effect Predictor.* Genome Biology, 17(1), 122. https://doi.org/10.1186/s13059-016-0974-4

- **vcfanno**
  Pedersen, B. S., Layer, R. M., & Quinlan, A. R. (2016). *Vcfanno: fast, flexible annotation of genetic variants.* Genome Biology, 17, 118. https://doi.org/10.1186/s13059-016-0973-5

- **LOFTEE** (when `--vep_lof_prediction`)
  Karczewski, K. J., Francioli, L. C., Tiao, G., et al. (2020). *The mutational constraint spectrum quantified from variation in 141,456 humans.* Nature, 581, 434–443. https://doi.org/10.1038/s41586-020-2308-7

### Annotation databases

- **dbNSFP** v4.5
  Liu, X., Li, C., Mou, C., Dong, Y., & Tu, Y. (2020). *dbNSFP v4: a comprehensive database of transcript-specific functional predictions and annotations for human nonsynonymous and splice-site SNVs.* Genome Medicine, 12, 103.

- **gnomAD** r2.1
  Karczewski, K. J., Francioli, L. C., Tiao, G., et al. (2020). *The mutational constraint spectrum quantified from variation in 141,456 humans.* Nature, 581, 434–443.

- **ClinVar** (December 2023)
  Landrum, M. J., Lee, J. M., Benson, M., et al. (2018). *ClinVar: improving access to variant interpretations and supporting evidence.* Nucleic Acids Research, 46(D1), D1062–D1067.

- **dbSNP** build 154
  Sherry, S. T., Ward, M. H., Kholodov, M., et al. (2001). *dbSNP: the NCBI database of genetic variation.* Nucleic Acids Research, 29(1), 308–311.

- **GENCODE** v44 / v19
  Frankish, A., Diekhans, M., Jungreis, I., et al. (2021). *GENCODE 2021.* Nucleic Acids Research, 49(D1), D916–D923.

- **NHGRI-EBI GWAS Catalog** (November 2023)
  Sollis, E., Mosaku, A., Abid, A., et al. (2023). *The NHGRI-EBI GWAS Catalog: knowledgebase and deposition resource.* Nucleic Acids Research, 51(D1), D977–D985.

- **CancerMine** v50
  Lever, J., Zhao, E. Y., Grewal, J., Jones, M. R., & Jones, S. J. M. (2019). *CancerMine: a literature-mined resource for drivers, oncogenes and tumor suppressors in cancer.* Nature Methods, 16, 505–507.

- **Cancer Hotspots**
  Chang, M. T., Asthana, S., Gao, S. P., et al. (2016). *Identifying recurrent mutations in cancer reveals widespread lineage diversity and mutational specificity.* Nature Biotechnology, 34, 155–163.

- **ncER**
  Wells, A., Heckerman, D., Torkamani, A., Yin, L., Sebat, J., Ren, B., Telenti, A., & Di Iulio, J. (2019). *Ranking of non-coding pathogenic variants and putative essential regions of the human genome.* Nature Communications, 10, 5241.

- **Oncogenicity classification** (when `--oncogenicity_annotation`)
  Horak, P., Griffith, M., Danos, A. M., et al. (2022). *Standards for the classification of pathogenicity of somatic variants in cancer (oncogenicity): Joint recommendations of Clinical Genome Resource (ClinGen), Cancer Genomics Consortium (CGC), and Variant Interpretation for Cancer Consortium (VICC).* Genetics in Medicine, 24, 986–998.

### Utilities used inside the gvanno container

- **HTSlib / bgzip / tabix** — Bonfield, J. K., Marshall, J., Danecek, P., et al. (2021). *HTSlib: C library for reading/writing high-throughput sequencing data.* GigaScience, 10(2), giab007.
- **bcftools / samtools** — Danecek, P., Bonfield, J. K., Liddle, J., et al. (2021). *Twelve years of SAMtools and BCFtools.* GigaScience, 10(2), giab008.
- **vcf2tsvpy** — https://github.com/sigven/vcf2tsvpy (Sigve Nakken)
