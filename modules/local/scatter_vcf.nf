process SCATTER_VCF {
    tag "${meta.id}"
    label 'process_low'
    container 'quay.io/biocontainers/bcftools:1.19--h8b25389_0'

    input:
    tuple val(meta), path(vcf), path(tbi)
    path  fai

    output:
    tuple val(meta), path("shards/*.vcf.gz"), path("shards/*.vcf.gz.tbi"), emit: shards
    path  "versions.yml", emit: versions

    script:
    """
    mkdir -p shards
    # one shard per primary contig (skip alt/unplaced via length filter)
    awk '\$2 > 1000000 {print \$1}' ${fai} | while read chr; do
        bcftools view -O z -o shards/${meta.id}.\${chr}.vcf.gz -r \${chr} ${vcf} || true
        if [ -s shards/${meta.id}.\${chr}.vcf.gz ]; then
            tabix -p vcf shards/${meta.id}.\${chr}.vcf.gz
        else
            rm -f shards/${meta.id}.\${chr}.vcf.gz
        fi
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bcftools: \$(bcftools --version | head -n1 | awk '{print \$2}')
    END_VERSIONS
    """
}
