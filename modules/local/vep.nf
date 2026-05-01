process VEP {
    tag "${meta.id}/${shard}"
    label 'process_vep'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi), val(shard)
    path  refdata_dir
    path  vep_cache

    output:
    tuple val(meta), path("*.vep.vcf.gz"), path("*.vep.vcf.gz.tbi"), val(shard), emit: vcf
    path  "*.log",       optional: true, emit: log
    path  "versions.yml", emit: versions

    script:
    def args      = task.ext.args   ?: ''
    def prefix    = task.ext.prefix ?: "${meta.id}.${shard}.vep"
    def assembly  = params.genomes[params.genome].assembly_dir
    def regulatory = params.vep_regulatory       ? '--vep_regulatory'      : ''
    def gencode    = params.vep_gencode_basic    ? '--vep_gencode_basic'   : ''
    def lof        = params.vep_lof_prediction   ? '--vep_lof_prediction'  : ''
    def nointer    = params.vep_no_intergenic    ? '--vep_no_intergenic'   : ''
    def debugflag  = params.keep_intermediates   ? '--debug'               : ''
    """
    # gvanno_vep.py expects vep_dir = the VEP cache root
    gvanno_vep.py \\
        ${vep_cache} \\
        ${vcf} \\
        ${prefix}.vcf \\
        ${assembly} \\
        ${params.vep_pick_order} \\
        ${regulatory} \\
        --vep_buffer_size ${params.vep_buffer_size} \\
        --vep_n_forks ${task.cpus} \\
        ${gencode} \\
        ${lof} \\
        ${nointer} \\
        ${debugflag} \\
        ${args} 2> ${prefix}.log

    # gvanno_vep.py may produce ${prefix}.vcf.gz directly. Fall back if not.
    if [ ! -f ${prefix}.vcf.gz ] && [ -f ${prefix}.vcf ]; then
        bgzip -f ${prefix}.vcf
        tabix -p vcf ${prefix}.vcf.gz
    elif [ -f ${prefix}.vcf.gz ] && [ ! -f ${prefix}.vcf.gz.tbi ]; then
        tabix -p vcf ${prefix}.vcf.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ensembl-vep: \$(vep --help 2>/dev/null | grep -oP 'ensembl-vep\\s+:\\s*\\K[\\d.]+' || echo 'unknown')
        gvanno:      \$(echo "${params.gvanno_container}" | sed 's/.*://')
    END_VERSIONS
    """
}
