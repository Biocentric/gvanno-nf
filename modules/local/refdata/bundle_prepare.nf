/*
 * Post-fetch reference preparation.
 *
 * The Ensembl primary-assembly FASTA ships as plain gzip; VEP needs it
 * BGZF-compressed and faidx'd, and stored at a hard-coded path inside the
 * VEP cache directory. This process does that prep, in-place, using the
 * gvanno container (bgzip + samtools both live there).
 *
 * Idempotent: skips work when the BGZF + .fai + .gzi files already exist.
 */
process BUNDLE_PREPARE {
    tag "${genome}/${params.refdata_version}"
    label 'process_low'
    container "${ params.gvanno_container }"

    input:
    val  genome
    path refdata_dir

    output:
    path  refdata_dir, includeInputs: true, emit: root
    path  "prepare.log",                    emit: log

    script:
    def assembly  = params.genomes[genome].assembly_dir
    def vep_asm   = params.genomes[genome].vep_assembly
    def ens_ver   = params.genomes[genome].ensembl_version
    def fasta_name = "Homo_sapiens.${vep_asm}.dna.primary_assembly.fa.gz"
    def vep_subdir = "data/${assembly}/.vep/homo_sapiens/${ens_ver}_${vep_asm}"
    """
    set -euo pipefail
    : > prepare.log

    DEST_DIR=${refdata_dir}/${vep_subdir}
    mkdir -p "\$DEST_DIR"
    DEST="\$DEST_DIR/${fasta_name}"

    # Locate the freshly downloaded FASTA. BUNDLE_FETCH leaves it as
    # ${refdata_dir}/data/${assembly}/.vep/ref.fa.gz; older layouts may
    # already have it placed at \$DEST.
    SRC="${refdata_dir}/data/${assembly}/.vep/ref.fa.gz"
    if [ ! -f "\$SRC" ] && [ ! -f "\$DEST" ]; then
        echo "[prepare] no FASTA found at \$SRC or \$DEST" | tee -a prepare.log
        exit 1
    fi

    # Skip if we already have a usable BGZF + indexes
    if [ -f "\$DEST" ] && [ -f "\$DEST.fai" ] && [ -f "\$DEST.gzi" ]; then
        echo "[prepare] FASTA already bgzipped + indexed at \$DEST — skipping" | tee -a prepare.log
        exit 0
    fi

    # Move the source into the canonical VEP location if needed
    if [ -f "\$SRC" ] && [ ! -f "\$DEST" ]; then
        echo "[prepare] moving FASTA to \$DEST" | tee -a prepare.log
        mv "\$SRC" "\$DEST"
    fi

    # Detect format. Ensembl ships plain gzip; we want BGZF.
    # gzip magic = 1f8b; BGZF is gzip + extra field FLG=0x04. file(1) reports
    # 'gzip compressed' for both, so we re-compress unconditionally if the
    # .gzi index is missing (BGZF requires .gzi to be useful here).
    if [ ! -f "\$DEST.gzi" ]; then
        echo "[prepare] re-encoding FASTA as BGZF (this can take a minute)" | tee -a prepare.log
        gunzip -f "\$DEST"
        bgzip "\${DEST%.gz}"
    fi

    if [ ! -f "\$DEST.fai" ]; then
        echo "[prepare] building .fai index" | tee -a prepare.log
        samtools faidx "\$DEST"
    fi

    # Stamp release notes if upstream bundle didn't ship one
    REL=${refdata_dir}/data/${assembly}/RELEASE_NOTES
    if [ ! -f "\$REL" ]; then
        echo "GVANNO_DB_VERSION = ${params.refdata_version}" > "\$REL"
    fi

    ls -lh "\$DEST"* | tee -a prepare.log
    echo "[prepare] done" | tee -a prepare.log
    """
}
