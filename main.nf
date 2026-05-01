#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Biocentric/gvanno-nf
    https://github.com/Biocentric/gvanno-nf
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Nextflow / nf-core style refactor of sigven/gvanno into a samplesheet-driven
    pipeline. Pinned to upstream gvanno 1.7.0 (VEP 110, refdata bundle 20231224).
    Original gvanno is the work of Sigve Nakken (University of Oslo); this is a
    workflow re-engineering only — all annotation logic and reference data come
    from the upstream gvanno project. https://github.com/sigven/gvanno
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

nextflow.enable.dsl = 2

include { GVANNO            } from './workflows/gvanno'
include { PREPARE_REFS_ONLY } from './workflows/gvanno'

def helpMessage() {
    log.info """
    gvanno-nf — germline variant annotation pipeline (nf-core style refactor of sigven/gvanno)

    Usage:
        nextflow run Biocentric/gvanno-nf -profile docker \\
            --input samplesheet.csv \\
            --genome GRCh38 \\
            --refdata_dir /path/to/refdata \\
            --outdir results

    Stage references only:
        nextflow run Biocentric/gvanno-nf -profile docker \\
            -entry PREPARE_REFERENCES \\
            --genome GRCh38 \\
            --refdata_dir /path/to/refdata \\
            --refdata_mode download

    Required:
        --input              CSV samplesheet with columns: sample,vcf,vcf_index
        --refdata_dir        Path to (or destination for) the gvanno bundle
        --genome             GRCh37 | GRCh38                              (default: GRCh38)

    Reference handling:
        --refdata_mode       prestaged | download                          (default: prestaged)
        --refdata_version    Bundle version, pinned to upstream            (default: 20231224)
        --refdata_url_base   Mirror list (tried in order)

    VEP tunables:
        --vep_n_forks                Default 4
        --vep_buffer_size            Default 500
        --vep_pick_order             Default mane_select,mane_plus_clinical,canonical,...
        --vep_regulatory             Off by default
        --vep_gencode_basic          Off by default
        --vep_lof_prediction         Off by default (required for --oncogenicity_annotation)
        --vep_no_intergenic          Off by default
        --vep_coding_only            Off by default

    Other:
        --vcfanno_n_processes        Default 4
        --oncogenicity_annotation    Requires --vep_lof_prediction
        --scatter_by                 none | chromosome                     (default: none)
        --keep_intermediates         Retain intermediate VCFs and logs
        --outdir                     Default ./results
    """
}

workflow {
    if ( params.help ) {
        helpMessage()
        return
    }
    GVANNO()
}

workflow PREPARE_REFERENCES {
    if ( params.help ) {
        helpMessage()
        return
    }
    PREPARE_REFS_ONLY()
}
