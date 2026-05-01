process SUMMARISE {
    tag "${meta.id}/${shard}"
    label 'process_medium'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi), val(shard)
    path  refdata_dir

    output:
    tuple val(meta), path("*.summarised.vcf.gz"), path("*.summarised.vcf.gz.tbi"), val(shard), emit: vcf
    path  "versions.yml", emit: versions

    script:
    def args        = task.ext.args   ?: ''
    def prefix      = task.ext.prefix ?: "${meta.id}.${shard}.vep.vcfanno.summarised"
    def assembly    = params.genomes[params.genome].assembly_dir
    def regulatory  = params.vep_regulatory          ? '1' : '0'
    def oncogenic   = params.oncogenicity_annotation ? '1' : '0'
    def debugflag   = params.keep_intermediates      ? '--debug' : ''
    """
    gvanno_summarise.py \\
        ${vcf} \\
        ${prefix}.vcf \\
        ${regulatory} \\
        ${oncogenic} \\
        ${params.vep_pick_order} \\
        ${refdata_dir}/data/${assembly} \\
        ${debugflag} \\
        --compress_output_vcf \\
        ${args}

    # gvanno_summarise.py with --compress_output_vcf already produces .vcf.gz + .tbi
    if [ ! -f ${prefix}.vcf.gz ] && [ -f ${prefix}.vcf ]; then
        bgzip -f ${prefix}.vcf
    fi
    if [ ! -f ${prefix}.vcf.gz.tbi ]; then
        tabix -p vcf ${prefix}.vcf.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gvanno: \$(echo "${params.gvanno_container}" | sed 's/.*://')
    END_VERSIONS
    """
}
