/*
 * Downloads the gvanno reference bundle (data bundle + VEP cache + LOFTEE ancestor).
 *
 * Tries each URL in params.refdata_url_base in order. For each base URL, the
 * fetch function first tries the file directly; if that 404s, it looks for a
 * `<file>.parts.txt` manifest listing chunked uploads (used by the GitHub
 * Releases mirror, since GH caps a single asset at 2 GB).
 *
 * Output is a `refdata_out/` directory with the bundle extracted plus the raw
 * (Ensembl-gzipped) FASTA at data/<assembly>/.vep/ref.fa.gz. BUNDLE_PREPARE
 * runs next to convert the FASTA to BGZF + faidx and place it where VEP wants.
 *
 * Container note: do NOT use `curlimages/curl` here. That image declares
 * ENTRYPOINT ["curl"], so Nextflow's `bash .command.run` invocation is passed
 * to curl as arguments — curl then reports `URL rejected: No host part in the
 * URL` and exits 3 before any of this script runs. It is also Alpine-based
 * (no bash).
 *
 * We reuse the gvanno container instead: it has no ENTRYPOINT, ships
 * bash/curl/wget/tar/gzip, and the user must pull it for the annotation steps
 * anyway — so the whole pipeline needs exactly one image.
 */
process BUNDLE_FETCH {
    tag "${genome}/${refdata_version}"
    label 'process_low'
    container "${ params.gvanno_container }"

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

    # ----------------------------------------------------------------------
    # fetch_first <output> <name> <base1> [<base2> ...]
    #   For each base URL, try direct fetch. If 404, try `<name>.parts.txt`
    #   manifest + reassemble chunks. Stops at first success.
    # ----------------------------------------------------------------------
    fetch_first() {
        local out=\$1; shift
        local name=\$1; shift
        for base in \$@; do
            local url="\${base%/}/\${name}"

            # 1. Try direct, single-file download
            echo "[fetch] trying \${url}" | tee -a fetch.log
            if curl -fSL --retry 5 --retry-delay 10 -o "\${out}" "\${url}"; then
                echo "[fetch] ok (direct) \${url}" | tee -a fetch.log
                return 0
            fi

            # 2. Try the chunked-manifest fallback (GH Releases mirror).
            # Scratch files stay in the task work dir, NOT /tmp: under
            # Singularity /tmp is bind-mounted from the host by default, so
            # concurrent fetches would clobber each other's parts/chunks.
            local manifest_url="\${url}.parts.txt"
            echo "[fetch] trying chunked \${manifest_url}" | tee -a fetch.log
            if curl -fSL --retry 3 --retry-delay 5 -o ./parts.txt "\${manifest_url}" 2>/dev/null; then
                echo "[fetch] manifest found, reassembling chunks" | tee -a fetch.log
                : > "\${out}"
                local part_ok=1
                while read -r part; do
                    [ -z "\${part}" ] && continue
                    local part_url="\${base%/}/\${part}"
                    echo "[fetch]   chunk \${part_url}" | tee -a fetch.log
                    if ! curl -fSL --retry 5 --retry-delay 10 -o ./chunk.tmp "\${part_url}"; then
                        echo "[fetch]   chunk failed" | tee -a fetch.log
                        part_ok=0
                        break
                    fi
                    cat ./chunk.tmp >> "\${out}"
                    rm -f ./chunk.tmp
                done < ./parts.txt
                rm -f ./parts.txt
                if [ "\$part_ok" = "1" ]; then
                    echo "[fetch] ok (chunked) \${url}" | tee -a fetch.log
                    return 0
                fi
            fi

            echo "[fetch] miss \${url}" | tee -a fetch.log
        done
        echo "[fetch] all mirrors failed for \${name}" | tee -a fetch.log
        return 1
    }

    # ----------------------------------------------------------------------
    # 1. gvanno annotation bundle (~3.7 GB compressed)
    # ----------------------------------------------------------------------
    BUNDLE=gvanno.databundle.${assembly}.${refdata_version}.tgz
    fetch_first refdata_out/\${BUNDLE} \${BUNDLE} ${url_list}
    tar -xzf refdata_out/\${BUNDLE} -C refdata_out/
    rm refdata_out/\${BUNDLE}

    # ----------------------------------------------------------------------
    # 2. VEP cache (Ensembl, single canonical URL — never chunked)
    # ----------------------------------------------------------------------
    CACHE=homo_sapiens_vep_${ens_ver}_${vep_asm}.tar.gz
    curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/\${CACHE} '${cache_url}'
    tar -xzf refdata_out/data/${assembly}/.vep/\${CACHE} -C refdata_out/data/${assembly}/.vep/
    rm refdata_out/data/${assembly}/.vep/\${CACHE}

    # ----------------------------------------------------------------------
    # 3. Reference FASTA (raw Ensembl gzip — BUNDLE_PREPARE will re-encode)
    # ----------------------------------------------------------------------
    curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/ref.fa.gz '${fasta_url}'

    # ----------------------------------------------------------------------
    # 4. LOFTEE ancestor (optional)
    # ----------------------------------------------------------------------
    if [ "${with_loftee}" = "true" ]; then
        for f in human_ancestor.fa.gz human_ancestor.fa.gz.fai human_ancestor.fa.gz.gzi; do
            curl -fSL --retry 5 -o refdata_out/data/${assembly}/.vep/\${f} '${anc_url}'/\${f}
        done
    fi

    if [ ! -f refdata_out/data/${assembly}/RELEASE_NOTES ]; then
        echo "GVANNO_DB_VERSION = ${refdata_version}" > refdata_out/data/${assembly}/RELEASE_NOTES
    fi

    echo "[fetch] complete" | tee -a fetch.log
    """
}
