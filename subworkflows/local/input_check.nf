/*
 * Parses the samplesheet and emits a per-sample channel.
 * Uses Nextflow's native splitCsv — keeps the dependency surface minimal so the
 * pipeline runs without nf-validation pre-installed.
 *
 * The optional `vcf_index` column is accepted for forward-compatibility but is
 * NOT required and is not carried downstream: VALIDATE_VCF re-normalises and
 * re-indexes every input, so a pre-existing .tbi is never consumed. This lets
 * the pipeline accept plain uncompressed .vcf inputs (no index at all).
 */
workflow INPUT_CHECK {
    take:
    samplesheet  // file

    main:
    Channel
        .fromPath(samplesheet, checkIfExists: true)
        .splitCsv(header: true, sep: ',')
        .map { row ->
            if (!row.sample) error "Samplesheet row missing 'sample' column: ${row}"
            if (!row.vcf)    error "Samplesheet row missing 'vcf' column: ${row}"
            def vcf  = file(row.vcf, checkIfExists: true)
            def meta = [ id: row.sample, variant_class: 'germline' ]
            tuple(meta, vcf)
        }
        .set { ch_vcfs }

    emit:
    vcfs = ch_vcfs    // [ meta, vcf ]
}
