include { INPUT_CHECK         } from '../subworkflows/local/input_check'
include { PREPARE_REFERENCES  } from '../subworkflows/local/prepare_references'
include { ANNOTATE_VARIANTS   } from '../subworkflows/local/annotate_variants'

workflow GVANNO {

    main:
    if ( !params.input )       error "Missing --input <samplesheet.csv>"
    if ( !params.refdata_dir ) error "Missing --refdata_dir <path>"
    if ( !(params.genome in params.genomes.keySet()) ) {
        error "Unknown --genome '${params.genome}'. Valid: ${params.genomes.keySet()}"
    }
    if ( params.oncogenicity_annotation && !params.vep_lof_prediction ) {
        error "--oncogenicity_annotation requires --vep_lof_prediction"
    }

    INPUT_CHECK ( file(params.input) )

    PREPARE_REFERENCES (
        params.genome,
        params.refdata_dir,
        params.refdata_version
    )

    ANNOTATE_VARIANTS (
        INPUT_CHECK.out.vcfs,
        PREPARE_REFERENCES.out.refdata_dir,
        PREPARE_REFERENCES.out.vep_cache
    )

    emit:
    vcf      = ANNOTATE_VARIANTS.out.vcf
    tsv      = ANNOTATE_VARIANTS.out.tsv
    versions = ANNOTATE_VARIANTS.out.versions
}

// Standalone reference preparation entrypoint
workflow PREPARE_REFS_ONLY {
    main:
    PREPARE_REFERENCES(
        params.genome,
        params.refdata_dir,
        params.refdata_version
    )
}
