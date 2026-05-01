process VALIDATE_VCF {
    tag "${meta.id}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi)
    path  refdata_dir

    output:
    tuple val(meta), path("*.gvanno_ready.vcf.gz"), path("*.gvanno_ready.vcf.gz.tbi"), emit: vcf
    path  "*.log",       optional: true, emit: log
    path  "versions.yml", emit: versions

    script:
    def args      = task.ext.args   ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}"
    def assembly  = params.genomes[params.genome].assembly_dir
    def debugflag = params.keep_intermediates ? '--debug' : ''
    """
    gvanno_validate_input.py \\
        ${refdata_dir}/data \\
        ${vcf} \\
        ${prefix}.gvanno_ready.vcf \\
        ${assembly} \\
        ${meta.id} \\
        --output_dir . \\
        ${debugflag} \\
        ${args} 2> ${prefix}.validate.log

    # gvanno_validate_input.py already produces ${prefix}.gvanno_ready.vcf.gz + .tbi.
    # Only fall back to manual bgzip/tabix if it skipped that step.
    if [ ! -f ${prefix}.gvanno_ready.vcf.gz ] && [ -f ${prefix}.gvanno_ready.vcf ]; then
        bgzip -f ${prefix}.gvanno_ready.vcf
        tabix -p vcf ${prefix}.gvanno_ready.vcf.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gvanno: \$(echo "${params.gvanno_container}" | sed 's/.*://')
        bcftools: \$(bcftools --version | head -n1 | awk '{print \$2}')
    END_VERSIONS
    """
}
