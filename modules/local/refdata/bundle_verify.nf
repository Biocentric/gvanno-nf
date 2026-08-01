/*
 * Verifies bundle presence, version, and (optionally) checksum.
 * The manifest file is always passed; if it's missing on disk, the script
 * skips the checksum step.
 */
process BUNDLE_VERIFY {
    tag "${genome}/${params.refdata_version}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    val  genome
    path refdata_dir
    path manifest, stageAs: 'manifest_in.tsv'

    output:
    path "verify.log", emit: log
    val  true,         emit: ok

    script:
    def assembly = params.genomes[genome].assembly_dir
    """
    set -euo pipefail
    : > verify.log

    REL=${refdata_dir}/data/${assembly}/RELEASE_NOTES
    if [ ! -f "\$REL" ]; then
        echo "[verify] missing RELEASE_NOTES at \$REL" | tee -a verify.log
        exit 1
    fi

    if ! grep -q "GVANNO_DB_VERSION = ${params.refdata_version}" "\$REL"; then
        echo "[verify] version mismatch in \$REL — expected ${params.refdata_version}" | tee -a verify.log
        cat "\$REL" | tee -a verify.log
        exit 1
    fi
    echo "[verify] version ok" | tee -a verify.log

    # Strip comments and blanks, then keep only entries for the assembly we are
    # actually verifying. One manifest covers every assembly of a bundle
    # version, but a user typically stages just one — without this filter,
    # sha256sum -c would fail on the other assembly's absent files.
    grep -vE '^\\s*(#|\$)' manifest_in.tsv \\
      | grep " data/${assembly}/" > manifest.clean.tsv || true
    if [ -s manifest.clean.tsv ]; then
        echo "[verify] checking sha256 against \$(wc -l < manifest.clean.tsv) entries" | tee -a verify.log
        ( cd ${refdata_dir} && sha256sum -c "\$OLDPWD/manifest.clean.tsv" ) | tee -a verify.log
    else
        echo "[verify] manifest is empty or comments-only — skipping checksum" | tee -a verify.log
    fi
    """
}
