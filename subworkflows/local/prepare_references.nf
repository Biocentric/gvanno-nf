include { BUNDLE_FETCH  } from '../../modules/local/refdata/bundle_fetch'
include { BUNDLE_VERIFY } from '../../modules/local/refdata/bundle_verify'

/*
 * Resolves a usable reference bundle.
 *   prestaged: assume params.refdata_dir already holds the bundle (default)
 *   download:  fetch into a Nextflow work dir; user is responsible for moving
 *              the resulting refdata_out/ contents to a permanent location
 *
 * If RELEASE_NOTES is missing in prestaged mode we abort with a clear message
 * pointing to -entry PREPARE_REFERENCES + --refdata_mode download.
 */
workflow PREPARE_REFERENCES {
    take:
    genome              // val
    refdata_dir_param   // val (path string or null)
    refdata_version     // val

    main:
    def assembly = params.genomes[genome].assembly_dir

    if ( params.refdata_mode == 'download' ) {
        BUNDLE_FETCH(
            genome,
            refdata_version,
            params.refdata_url_base,
            params.vep_lof_prediction
        )
        ch_root = BUNDLE_FETCH.out.root
    } else {
        // prestaged
        if ( !refdata_dir_param ) {
            error "refdata_mode=prestaged requires --refdata_dir <path>"
        }
        def staged = file(refdata_dir_param)
        def release_notes = file("${refdata_dir_param}/data/${assembly}/RELEASE_NOTES")
        if ( !release_notes.exists() ) {
            error """
            Reference bundle not found at ${refdata_dir_param}/data/${assembly}/.
            Either:
              - run with -entry PREPARE_REFERENCES --refdata_mode download to fetch it
              - or point --refdata_dir at an existing gvanno bundle (look for RELEASE_NOTES)
            """.stripIndent()
        }
        ch_root = Channel.value(staged)
    }

    // Optional checksum manifest shipped with the pipeline
    def manifest_file = file("${projectDir}/assets/refdata_manifest.${refdata_version}.tsv")

    BUNDLE_VERIFY( genome, ch_root, manifest_file )

    // Tie verification result into the downstream channel so processes can't
    // start until verification passes.
    ch_root_verified = ch_root.combine(BUNDLE_VERIFY.out.ok).map { root, _ok -> root }
    ch_vep_cache     = ch_root_verified.map { root -> file("${root}/data/${assembly}/.vep") }

    emit:
    refdata_dir = ch_root_verified
    vep_cache   = ch_vep_cache
}
