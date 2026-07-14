process SCATTER_VCF {
    tag "${meta.id}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcf), path(tbi)

    output:
    tuple val(meta), path("shards/*.vcf.gz"), path("shards/*.vcf.gz.tbi"), emit: shards
    path  "versions.yml", emit: versions

    script:
    """
    mkdir -p shards
    # Shard per contig actually present in the (already validated & normalised)
    # VCF. gvanno_validate_input.py has already restricted variants to
    # 1-22,X,Y,M/MT, so `tabix -l` returns only standard chromosomes and we do
    # not need to read a reference .fai. This is assembly-agnostic (works the
    # same for GRCh37 and GRCh38).
    for chr in \$(tabix -l ${vcf}); do
        bcftools view -O z -o "shards/${meta.id}.\${chr}.vcf.gz" -r "\${chr}" ${vcf}
        tabix -p vcf "shards/${meta.id}.\${chr}.vcf.gz"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bcftools: \$(bcftools --version | head -n1 | awk '{print \$2}')
    END_VERSIONS
    """
}
