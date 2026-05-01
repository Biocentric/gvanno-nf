process VCF2TSV {
    tag "${meta.id}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi)

    output:
    tuple val(meta), path("*.pass.tsv.gz"), path("*.all.tsv.gz"), emit: tsv
    path  "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}.gvanno"
    """
    # PASS-only
    vcf2tsvpy --input_vcf ${vcf} --compress --out_tsv ${prefix}.pass.tsv

    # all variants (keep rejected)
    vcf2tsvpy --input_vcf ${vcf} --compress --keep_rejected --out_tsv ${prefix}.all.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcf2tsvpy: \$(vcf2tsvpy --version 2>&1 | awk '{print \$NF}' || echo 'unknown')
    END_VERSIONS
    """
}
