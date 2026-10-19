# Verification, round 1

Verdict: verified

## Steps

1. `openlanes setup` from an empty directory: all ✓, installs nothing, exit 0: passed
2. gh logged out (GH_TOKEN=bad): gh ✗ with `gh auth login`, exit 69: passed
3. `openlanes setup -n`: installs nothing, lists what it would do: passed
4. Gem contains Brewfile, no bin/*; bin/setup works in checkout: passed (gem built with a temporary web/dist stub, removed afterwards)
5. `openlanes init` runs setup on a machine missing a tool, not on a ready one: passed

Note: magick has no usable font here, so captures are step-NN.txt and final.txt, not PNG.
