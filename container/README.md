# gvanno-nf container (Track B, VEP 115)

Builds `ghcr.io/biocentric/gvanno-nf:2026.2` — the gvanno helper scripts and
LOFTEE layered onto Ensembl's official VEP 115 image.

## Licence: MIT

`sigven/gvanno` is MIT-licensed as of
[`b25acdf`](https://github.com/sigven/gvanno/commit/b25acdf4cedda081d11bbf89ac537615ae1b7c63)
(2026-08-11) — Copyright © 2026 Sigve Nakken. Note the file is `LICENSE.md`,
not `LICENSE`, so a naive `raw/.../LICENSE` probe 404s.

The source is therefore **vendored** in [`gvanno-upstream/`](gvanno-upstream/),
and `LICENSE.md` sits beside it and is copied into the image — MIT requires the
notice to accompany copies, and the build asserts `test -f /gvanno/LICENSE.md`.

Patches are still applied at build time from [`patches/`](patches/) rather than
pre-applied into the vendored tree, so the delta from upstream stays auditable
as four small diffs. The build no longer fetches the helpers over the network,
which removes a supply-chain surface and a build-time failure mode.

> Before the licence existed this directory held only patches, and the
> Dockerfile fetched upstream's tarball at build time to avoid redistributing
> all-rights-reserved source. That indirection is gone.

## Upstream pin

```
sigven/gvanno @ b25acdf4cedda081d11bbf89ac537615ae1b7c63   (2026-08-11, the MIT commit)
```

Re-pinned from `379ee24` when the licence landed. The only difference between
them is `LICENSE.md` + `CODE_OF_CONDUCT.md` — **`src/gvanno/` is byte-identical**,
so behaviour matches everything the v0.3.0 gates validated and no revalidation
was owed. Confirmed empirically rather than assumed: `2026.2` produces
byte-identical output to `2026.1` on the 11-variant fixture and on the full
1,250-variant GRCh37 panel (193 columns, all 1,250 rows).

## The patches

| Patch | Change | Why |
|---|---|---|
| `lib_gvanno_gvanno_vars.py.patch` | `VEP_VERSION` 110→115, `GENCODE_VERSION[grch38]` 44→49 | Unavoidable. `VEP_VERSION` drives both `--cache_version` **and** the on-disk cache paths for the reference FASTA and the LOFTEE ancestral FASTA, so no bundle layout can work around it. |
| `gvanno_vep.py.patch` | adds `--af_gnomadg` on GRCh38 | `--af_gnomad` is a back-compat alias for `--af_gnomade` and yields **exome** frequencies only. The bundle declares 11 `gnomADg_*` tags that have never been populated in any release because this flag was never passed. Ensembl carries gnomAD genomes for GRCh38 only. |
| `lib_gvanno_vep.py.patch` | guards the inner `['SYMBOL']` key | The *outer* guard exists, but `make_transcript_xref_map` only creates an annotation key when the field is non-empty, so a transcript present in the map with a blank symbol raises `KeyError`. GENCODE 49 adds ~16k mostly unnamed loci. Line 233 already uses this pattern. |
| `lib_gvanno_utils.py.patch` | `exit(0)` → propagate the real exit code | `check_subprocess()` swallowed **every** external failure — including `vep` itself, `vcfanno`, `bcftools`, `vt` — and exited 0. A failing VEP run was indistinguishable from success and Nextflow never saw it. |

All four apply with `patch -p3 -F0` (zero fuzz) against the vendored tree — `-p3`
because `gvanno-upstream/` is rooted at `src/gvanno/`, which the patch headers
still name. Every patched file compiles.

## Base image

`ensemblorg/ensembl-vep:release_115.2` — Ubuntu 22.04.5, VEP 115.2, 258 MB
compressed (against 1.5 GB for `sigven/gvanno:1.7.0`).

Verified present by inspection:

- `/opt/vep/src/ensembl-vep/modules` — the exact path `get_loftee_dir()` hardcodes
- `bgzip`, `tabix`, `xxd`, `egrep`, `perl` 5.34
- every Perl module LOFTEE needs: `Bio::Perl`, `Bio::DB::HTS`,
  `Bio::DB::BigWig`, `DBD::SQLite`, `List::MoreUtils`

Verified **absent**, and therefore added by the Dockerfile:

- **Python 3 entirely** — `python` is a symlink to python2, no `python3`, no `pip3`
- `samtools` (LOFTEE shells out to it), `bcftools`, `vt`, `vcfanno`, `vcf2tsvpy`
- `NearestExonJB.pm` in `modules/` — it ships in `/plugins`, which is *not*
  where gvanno's `--dir_plugins` points
- `LoF.pm` — LOFTEE has never been part of `Ensembl/VEP_plugins` at any
  release; it is third-party at `konradjk/loftee`

`UTRannotator` is deliberately **not** carried over. Upstream's Dockerfile
`ADD`s it, but no gvanno module references it and it appears in no VEP
invocation.

## pandas is pinned below 3.0

Not stylistic. `lib/gvanno/variant.py:170-186` raises under pandas 3.0 —
`TypeError: Invalid value '-1' for dtype 'str'` — because pandas 3 removed
silent dtype coercion. Verified by execution, not inference. Fixing that
properly is a separate change; do not combine a pandas major with a VEP major.

## Build status — passing

Built and verified on hephaestus, 2026-08-09:

```
vep 115.2 · python3 3.10.12 · pandas 2.3.3 · numpy 2.2.6
samtools 1.13 · bcftools 1.13 · vcfanno 0.3.5 · vt 0.57721 · vcf2tsvpy 0.6.1
VEP_VERSION 115   GENCODE {'grch38': 49, 'grch37': 19}
all build-time assertions passed
```

**LOFTEE compiles against the VEP 115 Perl API.** This is the load-bearing
result for Track B, and it is now empirical rather than inferred:

```
perl -c LoF.pm            -> COMPILES
perl -c NearestExonJB.pm  -> COMPILES
```

The research argued LOFTEE would work because the plugin interface is
byte-identical across 110–116. This confirms the actual vendored 2019 LOFTEE
compiles against the actual 115 API inside the actual image. VEP's only
complaint when invoked is the missing cache, which B2 stages.

### Dependencies that are not obvious

Learned the hard way, one build failure each:

| Symptom | Cause |
|---|---|
| `no such option: --break-system-packages` | pip 22.0.2 on Ubuntu 22.04 predates the flag (pip 23.0.1), and PEP 668 marking only arrives in Ubuntu 23.04+ |
| `vcf2tsvpy (from versions: none)` | It is **not on PyPI** — bioconda and GitHub only, which is why sigven's image has it at `/conda/bin/`. Installed from the release tarball; it is MIT, so no redistribution question. |
| `Cannot find command 'git'` | The base image has no git; use a tarball URL, not `pip install git+https://` |
| `vt` 404 | The tag is `0.57721`, not a commit SHA. Its release tarball *does* bundle the vendored libs, so it builds without submodules. |
| `cannot find -lcurl` | The base has the curl *binary* but not `libcurl` headers; htslib also links `-lcrypto`. Needs `libcurl4-openssl-dev` + `libssl-dev`. |

Do not suppress compiler output in the vt step. The first failure there
reported only `Error 1` because of `>/dev/null 2>&1`, and finding the real
cause meant rebuilding the cached layer as a probe image.

## Build

```bash
bash container/build.sh                  # builds locally
bash container/build.sh --push           # also pushes to GHCR
```

Pushing to GHCR needs a token with `write:packages`; the token on hephaestus has
it. Pulling needs nothing — the package is public as of 2026-09-10.

Making it public was UI-only: GitHub has **no REST endpoint** for package
visibility, `PATCH /user/packages/container/<name>` 404s. The setting is at
<https://github.com/users/Biocentric/packages/container/gvanno-nf/settings>.
