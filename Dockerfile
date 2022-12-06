# This is a multi-stage image build.
#
# We first create a "builder" image and then create our final image by copying
# things from the builder image.  The point is to avoid bloating the final
# image with tools only needed during the image build.

# First build the temporary image.
FROM python:3.10-slim-bullseye AS builder

# Execute subsequent RUN statements with bash for handy modern shell features.
SHELL ["/bin/bash", "-c"]

# Add system deps for building
# autoconf, automake: for building VCFtools; may be used by package managers to build from source
# build-essential: contains gcc, g++, make, etc. for building various tools; may be used by package managers to build from source
# ca-certificates: for secure HTTPS connections
# curl: for downloading source files
# git: for git pip installs
# jq: used in builder-scripts/latest-augur-release-tag
# libsqlite3-dev: for building pyfastx (for Augur)
# pkg-config: for building VCFtools; may be used by package managers to build from source
# zlib1g-dev: for building VCFtools and pyfastx; may be used by package managers to build from source
# nodejs: for installing Auspice
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        libsqlite3-dev \
        pkg-config \
        zlib1g-dev

# Install a specific Node.js version
# https://github.com/nodesource/distributions/blob/0d81da75/README.md#installation-instructions
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
 && apt-get update && apt-get install -y nodejs

# Used for platform-specific instructions
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Add dependencies. All should be pinned to specific versions, except
# Nextstrain-maintained software.
# This includes pathogen-specific workflow dependencies. Since we only maintain a
# single Docker image to support all pathogen workflows, some pathogen-specific
# functionality must live in this Dockerfile. The following dependencies may be
# used by multiple pathogen workflows, but they have been commented according to
# the original pathogen that added these dependencies.

# Create directories to be copied in final stage.
RUN mkdir -p /final/bin /final/share /final/libexec


# 1. Build programs from source

# Build RAxML
# linux/arm64 does not support -mavx and -msse3 compilation flags which are used in the official repository.
# Make these changes in a fork for now: https://github.com/nextstrain/standard-RAxML/tree/simde
# TODO: Use the official repository if this PR is ever merged: https://github.com/stamatak/standard-RAxML/pull/50
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/nextstrain/standard-RAxML/tarball/4621552064304a219ff03810f5f0d91e1063b68f \
  | tar xzvpf - --no-same-owner --strip-components=1 \
  && make -f Makefile.AVX.PTHREADS.gcc \
  && cp -p raxmlHPC-PTHREADS-AVX /final/bin

# Build FastTree
WORKDIR /build/FastTree
RUN curl -fsSL https://api.github.com/repos/tsibley/FastTree/tarball/50c5b098ea085b46de30bfc29da5e3f113353e6f \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && make FastTreeDblMP \
 && cp -p FastTreeDblMP /final/bin

# Build vcftools
WORKDIR /build/vcftools
RUN curl -fsSL https://github.com/vcftools/vcftools/releases/download/v0.1.16/vcftools-0.1.16.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=2 \
 && ./configure --prefix=$PWD/built \
 && make && make install \
 && cp -rp built/bin/*    /final/bin \
 && cp -rp built/share/*  /final/share


# 2. Download pre-built programs

# Download MAFFT
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: https://mafft.cbrc.jp/alignment/software/installation_without_root.html
WORKDIR /download/mafft
RUN curl -fsSL https://mafft.cbrc.jp/alignment/software/mafft-7.475-linux.tgz \
  | tar xzvpf - --no-same-owner --strip-components=2 mafft-linux64/mafftdir/ \
 && cp -p bin/*     /final/bin \
 && cp -p libexec/* /final/libexec

# Download IQ-TREE
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: http://www.iqtree.org/doc/Compilation-Guide
WORKDIR /download/IQ-TREE
RUN curl -fsSL https://github.com/iqtree/iqtree2/releases/download/v2.1.2/iqtree-2.1.2-Linux.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && mv bin/iqtree2 /final/bin/iqtree

# Download Nextalign v1
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Example: https://github.com/nextstrain/nextclade/blob/1.11.0/.circleci/config.yml#L183-L223
RUN curl -fsSL -o /final/bin/nextalign1 https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextalign-Linux-x86_64

# Download Nextclade v1
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Example: https://github.com/nextstrain/nextclade/blob/1.11.0/.circleci/config.yml#L183-L223
RUN curl -fsSL -o /final/bin/nextclade1 https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextclade-Linux-x86_64

# Download tsv-utils
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: https://github.com/eBay/tsv-utils/tree/v2.2.0#build-from-source-files
RUN curl -L -o tsv-utils.tar.gz https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz \
 && tar -x --no-same-owner -v -C /final/bin -z --strip-components 2 --wildcards -f tsv-utils.tar.gz "*/bin/*" \
 && rm -f tsv-utils.tar.gz

# Download csvtk
RUN curl -L https://github.com/shenwei356/csvtk/releases/download/v0.24.0/csvtk_${TARGETOS}_${TARGETARCH}.tar.gz | tar xz --no-same-owner -C /final/bin

# Download seqkit
RUN curl -L https://github.com/shenwei356/seqkit/releases/download/v2.2.0/seqkit_${TARGETOS}_${TARGETARCH}.tar.gz | tar xz --no-same-owner -C /final/bin

# Download gofasta (for ncov/Pangolin)
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: https://github.com/virus-evolution/gofasta/tree/v0.0.6#installation
RUN curl -fsSL https://github.com/virus-evolution/gofasta/releases/download/v0.0.6/gofasta-linux-amd64 \
  -o /final/bin/gofasta

# Download minimap2 (for ncov/Pangolin)
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: https://github.com/lh3/minimap2/tree/v2.24#install
RUN curl -fsSL https://github.com/lh3/minimap2/releases/download/v2.24/minimap2-2.24_x64-linux.tar.bz2 \
  | tar xjvpf - --no-same-owner --strip-components=1 -C /final/bin minimap2-2.24_x64-linux/minimap2


# 3. Install programs via pip

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir==1.0.1

# Install tooling for our AWS Batch builds, which use `aws s3`.
RUN pip3 install awscli==1.18.195

# Install Snakemake and related optional dependencies.
RUN pip3 install snakemake==5.10.0
# Google Cloud Storage package is required for Snakemake to fetch remote files
# from Google Storage URIs.
RUN pip3 install google-cloud-storage==2.1.0

# Install epiweeks (for ncov)
RUN pip3 install epiweeks==2.1.2

# Install Pangolin and PangoLEARN + deps (for ncov)
# The cov-lineages projects aren't available on PyPI, so install via git URLs.
RUN pip3 install git+https://github.com/cov-lineages/pangolin.git@v3.1.17
RUN pip3 install git+https://github.com/cov-lineages/pangoLEARN.git@2021-12-06
RUN pip3 install git+https://github.com/cov-lineages/scorpio.git@v0.3.16
RUN pip3 install git+https://github.com/cov-lineages/constellations.git@v0.1.1
RUN pip3 install git+https://github.com/cov-lineages/pango-designation.git@19d9a537b9
RUN pip3 install pysam==0.19.1


# 4. Add unpinned programs and Nextstrain components

# Allow caching to be avoided from here on out by calling
# docker build --build-arg CACHE_DATE="$(date)"
ARG CACHE_DATE

# Install our own CLI so builds can do things like `nextstrain deploy`
RUN pip3 install nextstrain-cli

# Add helper scripts
COPY builder-scripts/ /builder-scripts/

# Nextclade/Nextalign v2 are downloaded directly but using the latest version,
# so they belong after CACHE_DATE (unlike Nextclade/Nextalign v1).

# Download Nextalign v2
# Set default Nextalign version to 2
RUN curl -fsSL -o /final/bin/nextalign2 https://github.com/nextstrain/nextclade/releases/latest/download/nextalign-$(/builder-scripts/target-triple) \
 && ln -sv nextalign2 /final/bin/nextalign

# Download Nextclade v2
# Set default Nextclade version to 2
RUN curl -fsSL -o /final/bin/nextclade2 https://github.com/nextstrain/nextclade/releases/latest/download/nextclade-$(/builder-scripts/target-triple) \
 && ln -sv nextclade2 /final/bin/nextclade

# Fauna
WORKDIR /nextstrain/fauna
RUN /builder-scripts/download-repo https://github.com/nextstrain/fauna master . \
 && pip3 install --requirement=requirements.txt

# Augur
# Augur is an editable install so we can overlay the augur version in the image
# with --volume=.../augur:/nextstrain/augur and still have it globally
# accessible and importable.
WORKDIR /nextstrain/augur
RUN /builder-scripts/download-repo https://github.com/nextstrain/augur "$(/builder-scripts/latest-augur-release-tag)" . \
 && pip3 install --editable .

# Auspice
# Install Node deps, build Auspice, and link it into the global search path.  A
# fresh install is only ~40 seconds, so we're not worrying about caching these
# as we did the Python deps.  Building auspice means we can run it without
# hot-reloading, which is time-consuming and generally unnecessary in the
# container image.  Linking is equivalent to an editable Python install and
# used for the same reasons described above.
WORKDIR /nextstrain/auspice
RUN /builder-scripts/download-repo https://github.com/nextstrain/auspice release . \
 && npm update && npm install && npm run build && npm link

# Add evofr for forecasting
RUN pip3 install evofr

# Add NCBI Datasets command line tools for access to NCBI Datsets Virus Data Packages
RUN curl -fsSL -o /final/bin/datasets https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-${TARGETARCH}/datasets
RUN curl -fsSL -o /final/bin/dataformat https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-${TARGETARCH}/dataformat

# ———————————————————————————————————————————————————————————————————— #

# Now build the final image.
FROM python:3.10-slim-bullseye AS final

# Add system runtime deps
# bzip2, gzip, xz-utils, zip, unzip, zstd: install compression tools
# ca-certificates: [Dockerfile] for secure HTTPS connections; may be used by workflows
# curl: [Dockerfile] for downloading binaries directly; may be used by workflows
# dos2unix: tsv-utils needs unix line endings
# jq: may be used by workflows
# less: for usability in an interactive prompt
# libsqlite3: for pyfastx (for Augur)
# perl: for running VCFtools
# ruby: may be used by workflows
# wget: may be used by workflows
# zlib1g: for pyfastx (for Augur)
# nodejs: for running Auspice
RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        curl \
        dos2unix \
        gzip \
        jq \
        less \
        libsqlite3-0 \
        perl \
        ruby \
        util-linux \
        wget \
        xz-utils \
        zip unzip \
        zlib1g \
        zstd

# Install a specific Node.js version
# https://github.com/nodesource/distributions/blob/0d81da75/README.md#installation-instructions
RUN curl -fsSL https://deb.nodesource.com/setup_16.x | bash - \
 && apt-get update && apt-get install -y nodejs

# Configure bash for interactive usage
COPY bashrc /etc/bash.bashrc

# Copy binaries
COPY --from=builder /final/bin/ /usr/local/bin/
COPY --from=builder /final/share/ /usr/local/share/
COPY --from=builder /final/libexec/ /usr/local/libexec/

# Set MAFFT_BINARIES explicitly for MAFFT
ENV MAFFT_BINARIES=/usr/local/libexec

# Ensure all container users can execute these programs
RUN chmod a+rx /usr/local/bin/* /usr/local/libexec/*

# Add installed Python libs
COPY --from=builder /usr/local/lib/python3.10/site-packages/ /usr/local/lib/python3.10/site-packages/

# Add installed Python scripts that we need.
#
# XXX TODO: This isn't great.  It's prone to needing manual updates because it
# doesn't pull in scripts which got installed but that we don't list.  Consider
# alternatives (like installing the deps into an empty prefix tree and then
# copying the whole prefix tree, or using pip's installed-files.txt manifests
# as the set of things to copy) in the future if the maintenance burden becomes
# troublesome or excessive.
#   -trs, 15 June 2018
COPY --from=builder \
    /usr/local/bin/augur \
    /usr/local/bin/aws \
    /usr/local/bin/envdir \
    /usr/local/bin/nextstrain \
    /usr/local/bin/pangolin \
    /usr/local/bin/pangolearn.smk \
    /usr/local/bin/scorpio \
    /usr/local/bin/snakemake \
    /usr/local/bin/

# Add installed Node libs
COPY --from=builder /usr/lib/node_modules/ /usr/lib/node_modules/

# Add globally linked Auspice script.
#
# This symlink is present in the "builder" image, but using COPY results in the
# _contents_ of the target being copied instead of a symlink being created.
# The symlink is required so that Auspice's locally-installed deps are
# correctly discovered by node.
RUN ln -sv /usr/lib/node_modules/auspice/auspice.js /usr/local/bin/auspice

# Add Nextstrain components
COPY --from=builder /nextstrain /nextstrain

# Add our entrypoints
COPY entrypoint entrypoint-aws-batch /sbin/
RUN chmod a+rx /sbin/entrypoint*

# Make /nextstrain a global HOME, writable by any UID (like /tmp)
RUN chmod a+rwXt /nextstrain
ENV HOME=/nextstrain

# Setup a non-root user for optional use
RUN useradd nextstrain \
    --system \
    --user-group \
    --shell /bin/bash \
    --home-dir /nextstrain \
    --no-log-init

# The host should bind mount the pathogen build dir into /nextstrain/build.
WORKDIR /nextstrain/build
RUN chown nextstrain:nextstrain /nextstrain/build

ENTRYPOINT ["/sbin/entrypoint"]

# Finally, add metadata at the end so it doesn't bust cached layers.
#
# Optionally passed in during build.  Used by a label below.
ARG GIT_REVISION

# Add some metadata to our image for searching later.  The "maintainer" label
# is community convention and comes from the old MAINTAINER command.  Other
# labels should be namedspaced a la Java classes.  We mostly use the keys
# defined in the OpenContainers spec:
#
#   https://github.com/opencontainers/image-spec/blob/master/annotations.md#pre-defined-annotation-keys
#
# The custom "org.nextstrain.image.name" label in particular will likely be
# used by nextstrain-cli's image pruning, as labels are the only way to have
# persistent metadata values (tags are removed from old images after pulling a
# new image with the tag).
LABEL maintainer="Nextstrain team <hello@nextstrain.org>"
LABEL org.opencontainers.image.authors="Nextstrain team <hello@nextstrain.org>"
LABEL org.opencontainers.image.source="https://github.com/nextstrain/docker-base"
LABEL org.opencontainers.image.revision="${GIT_REVISION}"
LABEL org.nextstrain.image.name="nextstrain/base"
