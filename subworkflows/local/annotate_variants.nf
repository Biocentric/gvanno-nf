include { VALIDATE_VCF    } from '../../modules/local/validate_vcf'
include { SCATTER_VCF     } from '../../modules/local/scatter_vcf'
include { VEP             } from '../../modules/local/vep'
include { VCFANNO         } from '../../modules/local/vcfanno'
include { SUMMARISE       } from '../../modules/local/summarise'
include { VCF2TSV         } from '../../modules/local/vcf2tsv'
include { FINALIZE_TSV    } from '../../modules/local/finalize_tsv'

/*
 * Per-sample annotation chain.
 * Tool-neutral name: a future PCGR entrypoint reuses this same subworkflow with
 * params.flavour='pcgr' and a different SUMMARISE/FINALIZE_TSV implementation.
 */
workflow ANNOTATE_VARIANTS {
    take:
    ch_vcfs            // [ meta, vcf, tbi ]
    ch_refdata_dir     // path
    ch_vep_cache       // path

    main:
    ch_versions = Channel.empty()

    VALIDATE_VCF ( ch_vcfs, ch_refdata_dir )
    ch_versions = ch_versions.mix(VALIDATE_VCF.out.versions)

    if ( params.scatter_by == 'chromosome' ) {
        // Pull fai from inside the bundle for splitting
        ch_fai = ch_refdata_dir.map { root ->
            def asm = params.genomes[params.genome].assembly_dir
            file("${root}/data/${asm}/.vep/ref.fa.fai")
        }
        SCATTER_VCF ( VALIDATE_VCF.out.vcf, ch_fai )

        // Flatten shards to one [meta,vcf,tbi,shard] per
        SCATTER_VCF.out.shards
            .flatMap { meta, vcfs, tbis ->
                vcfs.indices.collect { i ->
                    def shard = vcfs[i].name.replaceFirst(/^.*?\./,'').replaceFirst(/\.vcf\.gz$/,'')
                    tuple(meta, vcfs[i], tbis[i], shard)
                }
            }
            .set { ch_shards }
    } else {
        ch_shards = VALIDATE_VCF.out.vcf.map { meta, vcf, tbi -> tuple(meta, vcf, tbi, 'all') }
    }

    VEP        ( ch_shards,           ch_refdata_dir, ch_vep_cache )
    VCFANNO    ( VEP.out.vcf,          ch_refdata_dir )
    SUMMARISE  ( VCFANNO.out.vcf,      ch_refdata_dir )
    ch_versions = ch_versions.mix(VEP.out.versions, VCFANNO.out.versions, SUMMARISE.out.versions)

    // Gather shards back to a single VCF per sample.
    // When scatter_by=none, groupTuple sees a single tuple per meta and the
    // CONCAT_VCFS process takes its single-element branch (a cp).
    SUMMARISE.out.vcf
        .map { meta, vcf, tbi, _shard -> tuple(meta, vcf, tbi) }
        .groupTuple(by: 0)
        .set { ch_to_concat }

    CONCAT_VCFS ( ch_to_concat )
    ch_versions = ch_versions.mix(CONCAT_VCFS.out.versions)

    VCF2TSV       ( CONCAT_VCFS.out.vcf )
    FINALIZE_TSV  ( VCF2TSV.out.tsv, ch_refdata_dir )
    ch_versions = ch_versions.mix(VCF2TSV.out.versions, FINALIZE_TSV.out.versions)

    emit:
    vcf      = CONCAT_VCFS.out.vcf      // [ meta, vcf, tbi ]
    tsv      = FINALIZE_TSV.out.tsv     // [ meta, tsv ]
    versions = ch_versions
}

// Local concat helper — keeps everything in the gvanno container so we don't
// add a second image just for this. bcftools is already available there.
process CONCAT_VCFS {
    tag "${meta.id}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    tuple val(meta), path(vcfs), path(tbis)

    output:
    tuple val(meta), path("*.vcf.gz"), path("*.vcf.gz.tbi"), emit: vcf
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}.gvanno.${params.genomes[params.genome].vep_assembly}"
    if ( vcfs instanceof List && vcfs.size() > 1 ) {
        """
        bcftools concat -a -O z -o ${prefix}.vcf.gz ${vcfs.join(' ')}
        tabix -p vcf ${prefix}.vcf.gz

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            bcftools: \$(bcftools --version | head -n1 | awk '{print \$2}')
        END_VERSIONS
        """
    } else {
        """
        cp ${vcfs} ${prefix}.vcf.gz
        cp ${tbis} ${prefix}.vcf.gz.tbi

        cat <<-END_VERSIONS > versions.yml
        "${task.process}":
            bcftools: \$(bcftools --version | head -n1 | awk '{print \$2}')
        END_VERSIONS
        """
    }
}
