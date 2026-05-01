/*
 * Downloads the gvanno reference bundle (data bundle + VEP cache + LOFTEE ancestor).
 * Tries each URL in params.refdata_url_base in order.
 * Output is written to a 'refdata_out' directory which the caller stages or copies
 * to params.refdata_dir.
 */
process BUNDLE_FETCH {
    tag "${genome}/${refdata_version}"
    label 'process_low'
    container 'curlimages/curl:8.5.0'

    input:
    val genome
    val refdata_version
    val refdata_url_base
    val with_loftee

    output:
    path "refdata_out", emit: root
    path "fetch.log",   emit: log

    script:
    def assembly  = params.genomes[genome].assembly_dir
    def vep_asm   = params.genomes[genome].vep_assembly
    def ens_ver   = params.genomes[genome].ensembl_version
    def fasta_url = params.genomes[genome].fasta_url
    def cache_url = params.genomes[genome].vep_cache_url
    def anc_url   = params.genomes[genome].ancestor_url
    def url_list  = (refdata_url_base instanceof List ? refdata_url_base : [ refdata_url_base ]).join(' ')
    """
    set -euo pipefail
    mkdir -p refdata_out/data/${assembly}/.vep
    : > fetch.log

    fetch_first() {
        local out=\$1; shift
        local name=\$1; shift
        for base in \$@; do
            local url="\${base%/}/\${name}"
            echo "[fetch] trying \${url}" | tee -a fetch.log
            if curl -fSL --retry 5 --retry-delay 10 -o "\${out}" "\${url}"; then
                echo "[fetch] ok \${url}" | tee -a fetch.log
                return 0
            fi
            echo "[fetch] miss \${url}" | tee -a fetch.log
        done
        echo "[fetch] all mirrors failed for \${name}" | tee -a fetch.log
        return 1
    }

    # 1. gvanno annotation bundle
    BUNDLE=gvanno.databundle.${assembly}.${refdata_version}.tgz
    fetch_first refdata_out/\${BUNDLE} \${BUNDLE} ${url_list}
    tar -xzf refdata_out/\${BUNDLE} -C refdata_out/
    rm refdata_out/\${BUNDLE}

    # 2. VEP cache (Ensembl, single canonical URL)
    CACHE=homo_sapiens_vep_${ens_ver}_${vep_asm}.tar.gz
    curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/\${CACHE} '${cache_url}'
    tar -xzf refdata_out/data/${assembly}/.vep/\${CACHE} -C refdata_out/data/${assembly}/.vep/
    rm refdata_out/data/${assembly}/.vep/\${CACHE}

    # 3. Reference FASTA
    curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/ref.fa.gz '${fasta_url}'

    # 4. LOFTEE ancestor (optional)
    if [ "${with_loftee}" = "true" ]; then
        for f in human_ancestor.fa.gz human_ancestor.fa.gz.fai human_ancestor.fa.gz.gzi; do
            curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/\${f} '${anc_url}'/\${f}
        done
    fi

    # Stamp release notes if upstream bundle didn't ship one
    if [ ! -f refdata_out/data/${assembly}/RELEASE_NOTES ]; then
        echo "GVANNO_DB_VERSION = ${refdata_version}" > refdata_out/data/${assembly}/RELEASE_NOTES
    fi
    """
}
