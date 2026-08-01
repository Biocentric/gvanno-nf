# gvanno-nf reference bundle builder
#
#   make fetch          download every source (account-free; see config/sources.yml)
#   make cgc mim        build the two xref inputs that would otherwise need accounts
#   make spec           re-capture the format contract from the current bundle
#   make clean          remove build outputs (keeps downloaded sources)
#
# Everything is idempotent — re-running skips work already done.
#
# Design constraint: no step may require an account. COSMIC (Cancer Gene
# Census) and OMIM (genemap2) are replaced by an older PCGR bundle and NCBI
# mim2gene_medgen respectively. See config/sources.yml.

ASSEMBLY   ?= grch38
SRCDIR     ?= /mnt/big/gvanno-refdata
BUILDDIR   ?= /mnt/big/gvanno-build
OUTDIR     ?= $(BUILDDIR)/out
PRIOR      ?= $(BUILDDIR)/ref-20231224/data/$(ASSEMBLY)
STEPS      := ./steps

.PHONY: all fetch cgc mim spec clean help
.DEFAULT_GOAL := help

help:
	@sed -n '2,12p' Makefile | sed 's/^# \?//'

$(OUTDIR):
	@mkdir -p $(OUTDIR)

## fetch — all sources, both donor bundles plus the open primaries
fetch:
	$(STEPS)/fetch-sources.sh -d $(SRCDIR) -a $(ASSEMBLY)

## cgc — Cancer Gene Census v101, lifted from the PCGR 2.2-era bundle
##       (PCGR 2.3 dropped cgc_*; this avoids needing a COSMIC account)
cgc: | $(OUTDIR)
	$(STEPS)/extract-cgc.sh \
	    -b $(SRCDIR)/pcgr_ref_data.20250314.$(ASSEMBLY).tgz \
	    -w $(BUILDDIR)/pcgr-20250314 \
	    -o $(OUTDIR)/cgc.tsv

## mim — phenotype MIM numbers from NCBI, unioned with the prior bundle so the
##       result is strictly >= what we ship today (avoids needing OMIM access)
mim: | $(OUTDIR)
	@zcat $(PRIOR)/gene/tsv/gene_transcript_xref/gene_transcript_xref.tsv.gz \
	  | awk -F'\t' 'NR==1{for(i=1;i<=NF;i++){if($$i=="entrezgene")e=i;if($$i=="mim_phenotype_id")m=i};next} \
	      $$m!=""&&$$m!="NA"&&$$m!="."{print $$e"\t"$$m}' \
	  | sort -u > $(OUTDIR)/prior_mim.tsv
	$(STEPS)/extract-mim.sh \
	    -i $(SRCDIR)/mim2gene_medgen \
	    -u $(OUTDIR)/prior_mim.tsv \
	    -o $(OUTDIR)/mim_phenotype.tsv

## spec — regenerate the format contract from a bundle
spec:
	$(STEPS)/capture-spec.sh $(PRIOR) spec

clean:
	rm -rf $(OUTDIR)
