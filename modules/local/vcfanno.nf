process VCFANNO {
    tag "${meta.id}/${shard}"
    label 'process_medium'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi), val(shard)
    path  refdata_dir

    output:
    tuple val(meta), path("*.vcfanno.vcf.gz"), path("*.vcfanno.vcf.gz.tbi"), val(shard), emit: vcf
    path  "*.log",       optional: true, emit: log
    path  "versions.yml", emit: versions

    script:
    def args     = task.ext.args   ?: ''
    def prefix   = task.ext.prefix ?: "${meta.id}.${shard}.vep.vcfanno"
    def assembly = params.genomes[params.genome].assembly_dir
    """
    gvanno_vcfanno.py \\
        --num_processes ${task.cpus} \\
        --dbnsfp \\
        --gene_transcript_xref \\
        --clinvar \\
        --ncer \\
        --gwas \\
        ${vcf} \\
        ${prefix}.vcf \\
        ${refdata_dir}/data/${assembly} \\
        ${args} 2> ${prefix}.log

    if [ ! -f ${prefix}.vcf.gz ] && [ -f ${prefix}.vcf ]; then
        bgzip -f ${prefix}.vcf
    fi
    if [ ! -f ${prefix}.vcf.gz.tbi ]; then
        tabix -p vcf ${prefix}.vcf.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcfanno: \$(vcfanno 2>&1 | head -n1 | awk '{print \$2}' || echo 'unknown')
    END_VERSIONS
    """
}
