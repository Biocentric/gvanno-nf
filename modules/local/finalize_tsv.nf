process FINALIZE_TSV {
    tag "${meta.id}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(pass_tsv_gz, stageAs: 'input.pass.tsv.gz'), path(all_tsv_gz, stageAs: 'input.all.tsv.gz')
    path  refdata_dir

    output:
    tuple val(meta), path("*.pass.tsv.gz"), emit: tsv
    path  "versions.yml", emit: versions

    script:
    def prefix   = task.ext.prefix ?: "${meta.id}.gvanno"
    def assembly = params.genomes[params.genome].assembly_dir
    def asm_short = params.genomes[params.genome].vep_assembly.toLowerCase().replaceFirst('grch','grch')
    """
    gvanno_finalize.py \\
        ${refdata_dir}/data/${assembly} \\
        input.pass.tsv.gz \\
        finalize.out.tsv \\
        ${assembly} \\
        ${meta.id}

    # gvanno_finalize.py writes gzipped content into the file path it was given,
    # ignoring the lack of .gz extension. Detect this and rename rather than
    # re-compressing.
    if [ -f finalize.out.tsv ]; then
        if head -c 2 finalize.out.tsv | xxd -p | grep -q '^1f8b'; then
            mv finalize.out.tsv ${prefix}.pass.tsv.gz
        else
            gzip -f finalize.out.tsv
            mv finalize.out.tsv.gz ${prefix}.pass.tsv.gz
        fi
    elif [ -f finalize.out.tsv.gz ]; then
        mv finalize.out.tsv.gz ${prefix}.pass.tsv.gz
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gvanno: \$(echo "${params.gvanno_container}" | sed 's/.*://')
    END_VERSIONS
    """
}
