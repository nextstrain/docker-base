# This is a multi-stage image build.
#
# We first create two builder images (builder-build-platform,
# builder-target-platform). Then we create our final image by copying things
# from the builder images. The point is to avoid bloating the final image with
# tools only needed during the image build.

# Setup: pull cross-compilation tools.
FROM --platform=$BUILDPLATFORM tonistiigi/xx AS xx

# ———————————————————————————————————————————————————————————————————— #

# Define a builder stage that runs on the build platform.
# Even if the target platform is different, instructions will run natively for
# faster compilation.
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS builder-build-platform

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

# Copy cross-compilation tools.
COPY --from=xx / /

# Add system deps for building
# autoconf, automake: for building VCFtools; may be used by package managers to build from source
# ca-certificates: for secure HTTPS connections
# curl: for downloading source files
# git: used in builder-scripts/download-repo
# make: used for building from Makefiles (search for usage); may be used by package managers to build from source
# nodejs: for installing Auspice
# clang: for compiling C/C++ projects; may be used by package managers to build from source
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        clang \
        ca-certificates \
        curl \
        git \
        make \
        dpkg-dev

# Install a specific Node.js version
# https://github.com/nodesource/distributions/blob/ba48c1fe6e843e9ffb60aefc5da5d00234c83f04/README.md#using-debian-as-root-nodejs-20
RUN apt-get update && apt-get install -y curl \
 && curl -fsSL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh \
 && bash nodesource_setup.sh \
 && apt-get install -y nodejs

# Used for platform-specific instructions
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Install packages that generate binaries for the target architecture.
# https://github.com/tonistiigi/xx#building-on-debian
# binutils, gcc, libc6-dev: for compiling C/C++ programs (TODO: verify)
# g++: for building VCFtools; may be used by package managers to build from source
# pkg-config: for building VCFtools; may be used by package managers to build from source
# zlib1g-dev: for building VCFtools; may be used by package managers to build from source
RUN xx-apt-get install -y \
  binutils \
  gcc \
  g++ \
  libc6-dev \
  pkg-config \
  zlib1g-dev

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
# Some changes are necessary to allow the Makefile to work with cross-compilation.
# Make these changes in a fork for now: https://github.com/nextstrain/standard-RAxML/tree/fix-cross-compile
# TODO: Use the official repository if this PR is ever merged: https://github.com/stamatak/standard-RAxML/pull/50
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/nextstrain/standard-RAxML/tarball/4868de62a62be8901259807cfea26f336c2ca477 \
  | tar xzvpf - --no-same-owner --strip-components=1 \
  && CC=xx-clang make -f Makefile.AVX.PTHREADS.gcc \
  && cp -p raxmlHPC-PTHREADS-AVX /final/bin

# Build FastTree
WORKDIR /build/FastTree
RUN curl -fsSL https://api.github.com/repos/nextstrain/FastTree/tarball/df4212c8c9991e7e0d432e42d53c21cd8408a181 \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && CC=$(xx-info)-gcc make FastTreeDblMP \
 && cp -p FastTreeDblMP /final/bin

# Build vcftools
# Some unreleased changes are necessary to allow Autoconf to work with cross-compilation¹.
# ¹ https://github.com/vcftools/vcftools/commit/1cab5204eb0ce01664178bafd0ad6104525709d1
WORKDIR /build/vcftools
RUN curl -fsSL https://api.github.com/repos/vcftools/vcftools/tarball/1cab5204eb0ce01664178bafd0ad6104525709d1 \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && ./autogen.sh && ./configure --prefix=$PWD/built \
      --build=$(TARGETPLATFORM= xx-clang --print-target-triple) \
      --host=$(xx-clang --print-target-triple) \
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
RUN curl -fsSL https://github.com/iqtree/iqtree2/releases/download/v2.3.5.cmaple/iqtree-2.3.5.cmaple-Linux-intel.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && mv bin/iqtree2 /final/bin/iqtree

# Add helper scripts
COPY builder-scripts/ /builder-scripts/

# Download Nextalign v2
# Set default Nextalign version to 2
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/download/2.14.0/nextalign-$(/builder-scripts/target-triple) \
  -o /final/bin/nextalign2 \
  && ln -sv nextalign2 /final/bin/nextalign

# Download Nextclade v2
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/download/2.14.0/nextclade-$(/builder-scripts/target-triple) \
  -o /final/bin/nextclade2

# Download tsv-utils
# NOTE: Running this program requires support for emulation on the Docker host
# if the processor architecture is not amd64.
# TODO: Build from source to avoid emulation. Instructions: https://github.com/eBay/tsv-utils/tree/v2.2.0#build-from-source-files
RUN curl -L -o tsv-utils.tar.gz https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz \
 && tar -x --no-same-owner -v -C /final/bin -z --strip-components 2 --wildcards -f tsv-utils.tar.gz "*/bin/*" \
 && rm -f tsv-utils.tar.gz

# Download csvtk
RUN curl -L https://github.com/shenwei356/csvtk/releases/download/v0.30.0/csvtk_${TARGETOS}_${TARGETARCH}.tar.gz | tar xz --no-same-owner -C /final/bin

# Download seqkit
RUN curl -L https://github.com/shenwei356/seqkit/releases/download/v2.2.0/seqkit_${TARGETOS}_${TARGETARCH}.tar.gz | tar xz --no-same-owner -C /final/bin

# 3. Add unpinned programs

# Allow caching to be avoided from here on out in this stage by calling
# docker build --build-arg CACHE_DATE="$(date)"
# NOTE: All versioned software added below should be checked in
# devel/validate-platforms.
ARG CACHE_DATE

# Download Nextclade v3
# Set default Nextclade version to 3
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/latest/download/nextclade-$(/builder-scripts/target-triple) \
  -o /final/bin/nextclade3 \
  && ln -sv nextclade3 /final/bin/nextclade

# Auspice
# Building auspice means we can run it without hot-reloading, which is
# time-consuming and generally unnecessary in the container image.
# Linking is used so we can overlay the auspice version in the image with
# --volume=.../auspice:/nextstrain/auspice and still have it globally accessible
# and importable.
#
# Versions of NPM might differ in platform between where Auspice is installed
# and where it is used (the final image). This does not matter since Auspice
# (and its runtime dependencies at the time of writing) are not
# platform-specific.
# This may change in the future, which would call for cross-platform
# installation using npm_config_arch (if using node-gyp¹ or prebuild-install²)
# or npm_config_target_arch (if using node-pre-gyp³⁴).
#
# ¹ https://github.com/nodejs/node-gyp#environment-variables
# ² https://github.com/prebuild/prebuild-install#help
# ³ https://github.com/mapbox/node-pre-gyp#options
# ⁴ https://github.com/mapbox/node-pre-gyp/blob/v1.0.10/lib/node-pre-gyp.js#L186
WORKDIR /nextstrain/auspice
RUN /builder-scripts/download-repo https://github.com/nextstrain/auspice release . \
 && npm install --omit dev && npm link

# Add NCBI Datasets command line tools for access to NCBI Datsets Virus Data Packages
RUN curl -fsSL https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-${TARGETARCH}/datasets \
  -o /final/bin/datasets
RUN curl -fsSL https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-${TARGETARCH}/dataformat \
  -o /final/bin/dataformat

# ———————————————————————————————————————————————————————————————————— #

# Define a builder stage that runs on the target platform.
# If the target platform is different from the build platform, instructions will
# run under emulation which can be slower.
# This is in place for Python programs which are not easy to install for a
# different target platform¹.
# ¹ https://github.com/pypa/pip/issues/5453
FROM --platform=$TARGETPLATFORM python:3.11-slim-bookworm AS builder-target-platform

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

# Used for platform-specific instructions
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH

# Add system deps for building
# curl, jq: used in builder-scripts/latest-augur-release-tag
# git: for git pip installs
# gcc, libc6-dev: for building datrie (for Snakemake)
# make: for building isal (if necessary, for Augur)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        gcc \
        git \
        libc6-dev \
        make \
        jq


# 1. Install programs via pip

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir==1.0.1

# Install tooling for our AWS Batch builds, which use `aws s3`.
RUN python3 -m venv /usr/local/libexec/awscli \
 && /usr/local/libexec/awscli/bin/python -m pip install awscli==1.18.195 \
 && ln -sv /usr/local/libexec/awscli/bin/aws /usr/local/bin/aws

# Install Snakemake and related optional dependencies.
# Pinned to 9.6.2 for stability (latest version on 2025-07-03)
RUN pip3 install snakemake[reports]==9.6.2
# Snakemake plugins for remote storage providers
# Pinned for stability (latest versions on 2025-07-03)
RUN pip3 install snakemake-storage-plugin-http==0.3.0
RUN pip3 install snakemake-storage-plugin-s3==0.3.3

# Install epiweeks (for ncov)
RUN pip3 install epiweeks==2.1.2

# Install pango_aliasor (for forecasts-ncov)
RUN pip3 install pango_aliasor==0.3.0

RUN pip3 install pathogen-embed==3.0.0
RUN pip3 install xlrd==2.0.1

# Install openpyxl for pandas in GenoFLU
RUN pip3 install openpyxl==3.1.0

# Install pyarrow for pandas to support parquet files.
RUN pip3 install pyarrow==20.0.0

# Install bio, which is used by pathogen builds
RUN pip3 install bio==1.8.0

# 2. Add unpinned programs

# Allow caching to be avoided from here on out in this stage by calling
# docker build --build-arg CACHE_DATE="$(date)"
# NOTE: All versioned software added below should be checked in
# devel/validate-platforms.
ARG CACHE_DATE

# Add helper scripts
COPY builder-scripts/ /builder-scripts/

# Install our own CLI so builds can do things like `nextstrain deploy`
RUN pip3 install nextstrain-cli

# Fauna
WORKDIR /nextstrain/fauna
RUN /builder-scripts/download-repo https://github.com/nextstrain/fauna master . \
 && pip3 install --requirement=requirements.txt

# Add Treetime
RUN pip3 install phylo-treetime

# Augur
# Augur is an editable install so we can overlay the augur version in the image
# with --volume=.../augur:/nextstrain/augur and still have it globally
# accessible and importable.
WORKDIR /nextstrain/augur
RUN /builder-scripts/download-repo https://github.com/nextstrain/augur "$(/builder-scripts/latest-augur-release-tag)" . \
 && pip3 install --editable .

# Add evofr for forecasting
RUN pip3 install evofr

# ———————————————————————————————————————————————————————————————————— #

# Now build the final image.
FROM python:3.11-slim-bookworm AS final

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

# Add system runtime deps
# bzip2, gzip, xz-utils, zip, unzip, zstd: install compression tools
# ca-certificates: [Dockerfile] for secure HTTPS connections; may be used by workflows
# curl: [Dockerfile] for downloading binaries directly; may be used by workflows
# dos2unix: tsv-utils needs unix line endings
# git: used to clone workflows within a Docker instance (e.g., through GitPod)
# jq: may be used by workflows
# less: for usability in an interactive prompt
# libgomp1: for running FastTree
# libsqlite3: for pyfastx (for Augur)
# ncbi-blast+: for GenoFLU in avian-flu
# perl: for running VCFtools
# ruby: may be used by workflows
# sqlite3: for `augur merge`
# wget: may be used by workflows
# zlib1g: for pyfastx (for Augur)
# nodejs: for running Auspice
RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        curl \
        dos2unix \
        git \
        gzip \
        jq \
        less \
        libgomp1 \
        libsqlite3-0 \
        ncbi-blast+ \
        perl \
        ruby \
        sqlite3 \
        util-linux \
        wget \
        xz-utils \
        zip unzip \
        zlib1g \
        zstd

# Install a specific Node.js version
# https://github.com/nodesource/distributions/blob/ba48c1fe6e843e9ffb60aefc5da5d00234c83f04/README.md#using-debian-as-root-nodejs-20
RUN apt-get update && apt-get install -y curl \
 && curl -fsSL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh \
 && bash nodesource_setup.sh \
 && apt-get install -y nodejs

# Used for platform-specific instructions
ARG TARGETPLATFORM

# Configure bash for interactive usage
COPY bashrc /etc/bash.bashrc

# Copy binaries
COPY --from=builder-build-platform  /final/bin/     /usr/local/bin/
COPY --from=builder-build-platform  /final/share/   /usr/local/share/
COPY --from=builder-build-platform  /final/libexec/ /usr/local/libexec/

# Set MAFFT_BINARIES explicitly for MAFFT
ENV MAFFT_BINARIES=/usr/local/libexec

# Ensure all container users can execute these programs
RUN chmod a+rx /usr/local/bin/* /usr/local/libexec/*

# Add installed Python libs
COPY --from=builder-target-platform /usr/local/lib/python3.11/site-packages/ /usr/local/lib/python3.11/site-packages/

# AWS CLI
COPY --from=builder-target-platform /usr/local/libexec/awscli/ /usr/local/libexec/awscli/

# Add installed Python scripts that we need.
#
# XXX TODO: This isn't great.  It's prone to needing manual updates because it
# doesn't pull in scripts which got installed but that we don't list.  Consider
# alternatives (like installing the deps into an empty prefix tree and then
# copying the whole prefix tree, or using pip's installed-files.txt manifests
# as the set of things to copy) in the future if the maintenance burden becomes
# troublesome or excessive.
#   -trs, 15 June 2018
COPY --from=builder-target-platform \
    /usr/local/bin/augur \
    /usr/local/bin/aws \
    /usr/local/bin/bio \
    /usr/local/bin/envdir \
    /usr/local/bin/evofr \
    /usr/local/bin/nextstrain \
    /usr/local/bin/pathogen-distance \
    /usr/local/bin/pathogen-embed \
    /usr/local/bin/pathogen-cluster \
    /usr/local/bin/snakemake \
    /usr/local/bin/treetime \
    /usr/local/bin/

# Add installed Node libs
COPY --from=builder-build-platform /usr/lib/node_modules/ /usr/lib/node_modules/

# Add globally linked Auspice script.
#
# This symlink is present in the "builder" image, but using COPY results in the
# _contents_ of the target being copied instead of a symlink being created.
# The symlink is required so that Auspice's locally-installed deps are
# correctly discovered by node.
RUN ln -sv /usr/lib/node_modules/auspice/auspice.js /usr/local/bin/auspice

# Setup a non-root user for optional use
RUN useradd nextstrain \
    --system \
    --user-group \
    --shell /bin/bash \
    --home-dir /nextstrain \
    --no-log-init

# Add Nextstrain components
COPY --from=builder-build-platform  --chown=nextstrain:nextstrain /nextstrain /nextstrain
COPY --from=builder-target-platform --chown=nextstrain:nextstrain /nextstrain /nextstrain

# Add our entrypoints and helpers
COPY entrypoint entrypoint-aws-batch drop-privs create-envd delete-envd chdir-workdir /sbin/
RUN chmod a+rx /sbin/entrypoint* /sbin/drop-privs /sbin/{create,delete}-envd /sbin/chdir-workdir

# Make /nextstrain a global HOME, writable by any UID (like /tmp)
RUN chmod a+rwXt /nextstrain
ENV HOME=/nextstrain

# Run the final setup as our target user for permissions reasons.
USER nextstrain:nextstrain

# No nesting of runtimes, please.  Use the ambient runtime inside this runtime.
ENV NEXTSTRAIN_HOME=/nextstrain
RUN nextstrain check-setup --set-default ambient \
 && chown nextstrain:nextstrain /nextstrain/config \
 && chmod a+rw /nextstrain/config \
 && rm -f /nextstrain/lock

# The host should bind mount the pathogen build dir into /nextstrain/build.
WORKDIR /nextstrain/build
RUN chown nextstrain:nextstrain /nextstrain/build

# Switch back to root.  The entrypoint will drop to nextstrain:nextstrain as
# necessary when a container starts.
USER root
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
