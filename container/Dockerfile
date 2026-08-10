# gvanno-nf Track B container — Ensembl VEP 115 + the gvanno helper scripts.
#
# Layered on Ensembl's official image rather than building VEP from source:
# 258 MB vs 1.5 GB, and it already provides /opt/vep/src/ensembl-vep/modules,
# which is the path gvanno's get_loftee_dir() hardcodes.
#
# The gvanno helpers are fetched from GitHub at build time and patched here.
# They are NOT vendored into this repository: sigven/gvanno carries no licence,
# so redistributing its source is not ours to do. See README.md.
#
#   docker build -t ghcr.io/biocentric/gvanno-nf:2026.1 container/

FROM ensemblorg/ensembl-vep:release_115.2

# Final upstream commit. One past the v1.7.0 tag; the only difference is
# +1/-1 in download_gvanno_refdata.py, which we do not use, so the helpers are
# byte-identical to the tag that sigven/gvanno:1.7.0 was built from.
ARG GVANNO_COMMIT=379ee24247d1e7cac47884ac3b7488b6cfeccf7e
ARG LOFTEE_SHA=a4f160e06f9b340759727bf538bf33c54ba4958370be34c7a0cb4a35c9008b62

USER root
ENV DEBIAN_FRONTEND=noninteractive \
    VEP_DIR=/opt/vep/src/ensembl-vep \
    PYTHONDONTWRITEBYTECODE=1

# ---------------------------------------------------------------------------
# 1. Python 3 and the tools gvanno shells out to.
#    The base image has NO python3 at all (`python` is python2) and no
#    samtools/bcftools. LOFTEE shells out to samtools directly:
#    LoF.pm does `samtools faidx $human_ancestor_location $region`.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-dev \
        samtools bcftools \
        build-essential zlib1g-dev libbz2-dev liblzma-dev curl ca-certificates patch \
    && ln -sf /usr/bin/python3 /usr/local/bin/python \
    && rm -rf /var/lib/apt/lists/*

# pandas <3.0 is REQUIRED, not preference: lib/gvanno/variant.py:170-186 raises
# under pandas 3 ("Invalid value '-1' for dtype 'str'") because pandas 3 removed
# silent dtype coercion. Verified by execution. See README.md.
# No --break-system-packages: Ubuntu 22.04 ships pip 22.0.2, which predates the
# flag (pip 23.0.1), and does not mark its Python externally managed anyway
# (PEP 668 landed in 23.04+). Add it back only if the base moves to 24.04.
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel \
    && pip3 install --no-cache-dir \
        'pandas>=2.0,<3.0' 'numpy<2.3' scipy cython cyvcf2 vcf2tsvpy

# ---------------------------------------------------------------------------
# 2. vcfanno and vt — single static binary and a small source build.
# ---------------------------------------------------------------------------
ARG VCFANNO_VERSION=0.3.5
RUN curl -fsSL -o /usr/local/bin/vcfanno \
      "https://github.com/brentp/vcfanno/releases/download/v${VCFANNO_VERSION}/vcfanno_linux64" \
    && chmod +x /usr/local/bin/vcfanno

ARG VT_COMMIT=2187ff6347086e38f71a45c88faf768e9019be1f
RUN curl -fsSL -o /tmp/vt.tgz "https://codeload.github.com/atks/vt/tar.gz/${VT_COMMIT}" \
    && tar -xzf /tmp/vt.tgz -C /tmp && cd /tmp/vt-${VT_COMMIT} \
    && make -j"$(nproc)" >/dev/null && cp vt /usr/local/bin/ \
    && cd / && rm -rf /tmp/vt*

# ---------------------------------------------------------------------------
# 3. Plugins into the directory gvanno actually points --dir_plugins at.
#    The base ships NearestExonJB.pm in /plugins, which is NOT that directory.
#    LOFTEE has never been part of Ensembl/VEP_plugins — it is third-party.
#    gvanno uses konradjk/loftee's *grch38* branch for BOTH assemblies.
# ---------------------------------------------------------------------------
RUN cp /plugins/NearestExonJB.pm ${VEP_DIR}/modules/ \
    && curl -fsSL -o /tmp/loftee.tgz \
        "https://github.com/sigven/gvanno/raw/${GVANNO_COMMIT}/src/loftee_1.0.3.tgz" \
    && echo "${LOFTEE_SHA}  /tmp/loftee.tgz" | sha256sum -c - \
    && tar -xzf /tmp/loftee.tgz -C ${VEP_DIR}/modules/ \
    && rm -f /tmp/loftee.tgz \
    && test -f ${VEP_DIR}/modules/LoF.pm \
    && test -f ${VEP_DIR}/modules/NearestExonJB.pm

# ---------------------------------------------------------------------------
# 4. The gvanno helpers: fetch pinned, apply our patches, install to /gvanno.
# ---------------------------------------------------------------------------
COPY patches/ /tmp/patches/
RUN curl -fsSL -o /tmp/gvanno.tgz \
        "https://codeload.github.com/sigven/gvanno/tar.gz/${GVANNO_COMMIT}" \
    && tar -xzf /tmp/gvanno.tgz -C /tmp \
    && cd /tmp/gvanno-${GVANNO_COMMIT} \
    && for p in /tmp/patches/*.patch; do \
         echo "applying $(basename "$p")"; patch -p1 -F0 < "$p" || exit 1; \
       done \
    && mkdir -p /gvanno \
    && cp -r src/gvanno/. /gvanno/ \
    && chmod +x /gvanno/*.py \
    && cd / && rm -rf /tmp/gvanno* /tmp/patches

ENV PATH="/gvanno:${PATH}" \
    PYTHONPATH="/gvanno/lib:${PYTHONPATH}"

# ---------------------------------------------------------------------------
# 5. Fail the BUILD rather than a downstream run.
#    Every one of these silently degrades annotation if it is missing, and the
#    pipeline would still report success — that is the failure mode this whole
#    release is trying to design out.
# ---------------------------------------------------------------------------
RUN set -e; \
    for c in vep python3 samtools bcftools bgzip tabix vt vcfanno vcf2tsvpy xxd; do \
        command -v "$c" >/dev/null || { echo "MISSING: $c"; exit 1; }; done; \
    for m in Bio::Perl Bio::DB::HTS Bio::DB::BigWig DBD::SQLite List::MoreUtils; do \
        perl -M"$m" -e1 || { echo "MISSING perl module: $m"; exit 1; }; done; \
    python3 -c "import pandas, numpy, scipy, cyvcf2; \
        assert pandas.__version__ < '3', 'pandas 3 breaks variant.py'; \
        print('py stack ok: pandas', pandas.__version__, 'numpy', numpy.__version__)"; \
    python3 -c "import sys; sys.path.insert(0,'/gvanno/lib'); \
        from gvanno import gvanno_vars as v; \
        assert v.VEP_VERSION == '115', v.VEP_VERSION; \
        assert v.GENCODE_VERSION['grch38'] == 49, v.GENCODE_VERSION; \
        print('gvanno_vars ok:', v.VEP_VERSION, v.GENCODE_VERSION)"; \
    for h in gvanno_validate_input.py gvanno_vep.py gvanno_vcfanno.py \
             gvanno_summarise.py gvanno_finalize.py; do \
        command -v "$h" >/dev/null || { echo "MISSING helper: $h"; exit 1; }; done; \
    grep -q 'af_gnomadg' /gvanno/gvanno_vep.py || { echo "gnomadg patch missing"; exit 1; }; \
    grep -q 'exit(e.returncode' /gvanno/lib/gvanno/utils.py || { echo "exitcode patch missing"; exit 1; }; \
    echo "all build-time assertions passed"

LABEL org.opencontainers.image.title="gvanno-nf" \
      org.opencontainers.image.description="Ensembl VEP 115 + gvanno helpers for Biocentric/gvanno-nf" \
      org.opencontainers.image.source="https://github.com/Biocentric/gvanno-nf" \
      org.opencontainers.image.base.name="ensemblorg/ensembl-vep:release_115.2" \
      io.biocentric.gvanno.upstream-commit="${GVANNO_COMMIT}"

WORKDIR /data
