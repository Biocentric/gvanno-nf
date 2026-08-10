include { BUNDLE_FETCH   } from '../../modules/local/refdata/bundle_fetch'
include { BUNDLE_PREPARE } from '../../modules/local/refdata/bundle_prepare'
include { BUNDLE_VERIFY  } from '../../modules/local/refdata/bundle_verify'

/*
 * Resolves a usable reference bundle.
 *
 *   prestaged (default) — params.refdata_dir already holds the bundle.
 *   download            — fetch + prepare into params.refdata_dir.
 *
 * Both modes end up emitting the SAME shape: a bundle root that contains
 * data/<assembly>/..., so everything downstream is mode-agnostic.
 *
 * Download is idempotent at the workflow level: if the bundle is already
 * present and its RELEASE_NOTES matches params.refdata_version, the fetch is
 * skipped entirely and the existing copy is reused. That makes re-running
 * `--step prepare_references` cheap instead of re-pulling ~25 GB. (We do this
 * check in Groovy rather than relying on the process-level storeDir skip,
 * which does not fire reliably for a directory output.)
 */
workflow PREPARE_REFERENCES {
    take:
    genome              // val
    refdata_dir_param   // val (path string or null)
    refdata_version     // val

    main:
    def assembly = params.genomes[genome].assembly_dir

    if ( !refdata_dir_param ) {
        error "--refdata_dir <path> is required (destination in download mode, source in prestaged mode)"
    }

    // Strip trailing slashes so joined paths and error messages stay readable
    // (a user-supplied ".../grch38/" otherwise yields ".../grch38//data/...").
    def refdata_root = refdata_dir_param.toString().replaceAll('/+$', '')

    def release_notes  = file("${refdata_root}/data/${assembly}/RELEASE_NOTES")
    def already_staged = release_notes.exists() &&
                         release_notes.text.contains("GVANNO_DB_VERSION = ${refdata_version}")

    if ( params.refdata_mode == 'download' && !already_staged ) {
        BUNDLE_FETCH(
            genome,
            refdata_version,
            params.refdata_url_base,
            params.vep_lof_prediction
        )
        // BUNDLE_FETCH declares `storeDir params.refdata_dir`, so its `data`
        // output is written to <refdata_dir>/data rather than being left to rot
        // in the Nextflow work dir. BUNDLE_PREPARE then edits it in place there.
        BUNDLE_PREPARE( genome, BUNDLE_FETCH.out.data )
        ch_root = BUNDLE_PREPARE.out.data.map { file(refdata_root) }
    }
    else {
        if ( !release_notes.exists() ) {
            // Work out WHY it's missing so the message is actionable rather than
            // just echoing a path back at the user.
            def diagnosis = []

            def assembly_suffix = "/data/${assembly}"
            if ( file("${refdata_root}/RELEASE_NOTES").exists() ) {
                // --refdata_dir points INTO the bundle (at the assembly dir)
                // rather than at its root. Very easy mistake: that directory
                // looks like "the data" when you list it.
                def suggested = refdata_root.endsWith(assembly_suffix)
                    ? refdata_root[0..<(refdata_root.length() - assembly_suffix.length())]
                    : '<the directory that contains data/>'
                diagnosis << "--refdata_dir appears to point at the ASSEMBLY directory, not the bundle root."
                diagnosis << "The root is the directory that CONTAINS data/${assembly}/. Try:"
                diagnosis << ""
                diagnosis << "    --refdata_dir ${suggested}"
            }
            else {
                // Right root, wrong --genome?
                params.genomes.keySet().findAll { it != genome }.each { other ->
                    def other_dir = params.genomes[other].assembly_dir
                    if ( file("${refdata_root}/data/${other_dir}/RELEASE_NOTES").exists() ) {
                        diagnosis << "Found a ${other} bundle at this location, but --genome is ${genome}."
                        diagnosis << "Either pass --genome ${other}, or point --refdata_dir at a ${genome} bundle."
                    }
                }
            }

            if ( !diagnosis ) {
                diagnosis << "Either:"
                diagnosis << "  - run with --step prepare_references --refdata_mode download to fetch it"
                diagnosis << "  - or point --refdata_dir at an existing gvanno bundle"
            }

            error( ( [ "",
                       "Reference bundle not found: expected ${refdata_root}${assembly_suffix}/RELEASE_NOTES",
                       "" ] + diagnosis + [ "" ] ).join('\n') )
        }
        if ( params.refdata_mode == 'download' ) {
            log.info "[nf-gvanno] Reference bundle ${refdata_version} already present at " +
                     "${refdata_root} — skipping download."
        }
        ch_root = Channel.value(file(refdata_root))
    }

    // Optional checksum manifest shipped with the pipeline
    def manifest_file = file("${projectDir}/assets/refdata_manifest.${refdata_version}.tsv")

    BUNDLE_VERIFY( genome, ch_root, manifest_file )

    // Tie verification into the downstream channel so annotation processes
    // cannot start until verification passes.
    ch_root_verified = ch_root.combine(BUNDLE_VERIFY.out.ok).map { root, _ok -> root }
    ch_vep_cache     = ch_root_verified.map { root -> file("${root}/data/${assembly}/.vep") }

    emit:
    // .first() converts these back to VALUE channels. They must be values, not
    // queues: .combine() above demotes ch_root's value channel to a queue with
    // exactly one element, and a process invoked as
    // VEP(<24-shard queue>, <1-item queue>, <1-item queue>) zips its inputs
    // positionally and stops at the SHORTEST -- so only one shard is ever
    // annotated and the other 23 are silently discarded, with exit 0.
    // Invisible when scatter_by=none, because there is only one shard.
    refdata_dir = ch_root_verified.first()
    vep_cache   = ch_vep_cache.first()
}
