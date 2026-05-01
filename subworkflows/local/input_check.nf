/*
 * Parses the samplesheet and emits a per-sample channel.
 * Uses Nextflow's native splitCsv — keeps the dependency surface minimal so the
 * pipeline runs without nf-validation pre-installed.
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
            def vcf = file(row.vcf, checkIfExists: true)
            def tbi = row.vcf_index ? file(row.vcf_index, checkIfExists: true)
                                    : file("${row.vcf}.tbi")
            def meta = [ id: row.sample, variant_class: 'germline' ]
            tuple(meta, vcf, tbi)
        }
        .set { ch_vcfs }

    emit:
    vcfs = ch_vcfs    // [ meta, vcf, tbi ]
}
