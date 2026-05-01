#!/usr/bin/env python3
"""
Reserved for v0.2 when we drop the gvanno container and call vcfanno directly.

In v0.1 we use gvanno_vcfanno.py from inside sigven/gvanno:1.7.0, which
already knows how to find its own TOMLs and DB files relative to a passed
data directory — so nothing needs patching.

This stub exists so the eventual replacement has a stable home.
"""
import sys

if __name__ == "__main__":
    print("patch_vcfanno_toml.py is a v0.2 placeholder; no action taken.", file=sys.stderr)
    sys.exit(0)
