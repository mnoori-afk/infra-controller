# Image provenance — read before deploying anything

## The validated k3s-campaign image (all results in this directory)

Every number in these snapshots was produced by:

    nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:v2.1.0-pr-478-gc06f4787a-instrumented
    digest sha256:297814d3b59597b38fd6e1d6e64360369d1892fe3e04cd498d4deeafcf978f2d

Contents: upstream commit c06f4787a ("Fix regression in secure DiscoverMachine
with assigned instances", v2.1.0-pr-478 — the ingestion-tuning campaign's
pinned build) PLUS one instrumentation commit (9c27ccbf6 on the dev box's
`milad/3738-state-machine-timing` branch — same instrumentation now carried
by THIS branch's commit). Deployed with the helm chart from that same pinned
checkout. machine-a-tron image tag used in all runs:
`v2.1.0-pr-310-gb20d9f43c`.

## For benchmarks of THIS branch (do not reuse the tag above)

This branch (`milad/feat/stage-timing-benchmark`) = latest main
+ observability stack + the same instrumentation. The published
`-instrumented` tag does NOT contain latest main or the observability commit.
Build fresh from this branch and tag with its own identity, e.g.:

    docker build -f dev/docker/Dockerfile.release-container-x86_64 \
      --build-arg CONTAINER_BUILD_X86_64=nvcr.io/0837451325059433/carbide-dev/build-container-x86_64:latest \
      --build-arg CONTAINER_RUNTIME_X86_64=nvcr.io/0837451325059433/carbide-dev/runtime-container-x86_64:latest \
      -t nvmetal-carbide:stage-timing-$(git rev-parse --short HEAD) .
    # push as nvcr.io/0837451325059433/carbide-dev/nvmetal-carbide:<same tag> if needed

Comparing this branch's benchmark numbers against the CSVs here compares
different code bases (pin-era vs latest main) on different hardware — valid
for method and rough shape, not for regression math.
