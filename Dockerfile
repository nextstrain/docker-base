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
RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash - \
 && apt-get update && apt-get install -y nodejs

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
# AVX should be widely-supported enough
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/stamatak/standard-RAxML/tarball/v8.2.12 \
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
WORKDIR /download/mafft
RUN curl -fsSL https://mafft.cbrc.jp/alignment/software/mafft-7.475-linux.tgz \
  | tar xzvpf - --no-same-owner --strip-components=2 mafft-linux64/mafftdir/ \
 && cp -p bin/*     /final/bin \
 && cp -p libexec/* /final/libexec

# Download IQ-TREE
WORKDIR /download/IQ-TREE
RUN curl -fsSL https://github.com/iqtree/iqtree2/releases/download/v2.1.2/iqtree-2.1.2-Linux.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=1 \
 && mv bin/iqtree2 /final/bin/iqtree

# Download Nextalign v1
RUN curl -fsSL -o /final/bin/nextalign1 https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextalign-Linux-x86_64

# Download Nextclade v1
RUN curl -fsSL -o /final/bin/nextclade1 https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextclade-Linux-x86_64

# Download tsv-utils
RUN curl -L -o tsv-utils.tar.gz https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz \
 && tar -x --no-same-owner -v -C /final/bin -z --strip-components 2 --wildcards -f tsv-utils.tar.gz "*/bin/*" \
 && rm -f tsv-utils.tar.gz

# Download csvtk
RUN curl -L https://github.com/shenwei356/csvtk/releases/download/v0.24.0/csvtk_linux_amd64.tar.gz | tar xz --no-same-owner -C /final/bin

# Download seqkit
RUN curl -L https://github.com/shenwei356/seqkit/releases/download/v2.2.0/seqkit_linux_amd64.tar.gz | tar xz --no-same-owner -C /final/bin

# Download gofasta (for ncov/Pangolin)
RUN curl -fsSL https://github.com/virus-evolution/gofasta/releases/download/v0.0.6/gofasta-linux-amd64 \
  -o /final/bin/gofasta

# Download minimap2 (for ncov/Pangolin)
RUN curl -fsSL https://github.com/lh3/minimap2/releases/download/v2.24/minimap2-2.24_x64-linux.tar.bz2 \
  | tar xjvpf - --no-same-owner --strip-components=1 -C /final/bin minimap2-2.24_x64-linux/minimap2

# 3. Install programs via pip

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir==1.0.1

# Install tooling for our AWS Batch builds, which use `aws s3`.
RUN pip3 install awscli==1.18.195

# Install Snakemake and related optional dependencies.
RUN pip3 install snakemake==6.8.0
# Google Cloud Storage package is required for Snakemake to fetch remote files
# from Google Storage URIs.
RUN pip3 install google-cloud-storage==2.1.0

# Install epiweeks (for ncov)
RUN pip3 install epiweeks==2.1.2

# Install Pangolin and PangoLEARN + deps (for ncov)
# The cov-lineages projects aren't available on PyPI, so install via git URLs.
RUN pip3 install git+https://github.com/cov-lineages/pangolin.git@v4.1.3
RUN pip3 install git+https://github.com/cov-lineages/pangolin-data.git@v1.16
RUN pip3 install git+https://github.com/cov-lineages/scorpio.git@v0.3.17
RUN pip3 install git+https://github.com/cov-lineages/constellations.git@v0.1.10
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
RUN curl -fsSL -o /final/bin/nextalign2 https://github.com/nextstrain/nextclade/releases/latest/download/nextalign-x86_64-unknown-linux-gnu \
 && ln -sv nextalign2 /final/bin/nextalign

# Download Nextclade v2
# Set default Nextclade version to 2
RUN curl -fsSL -o /final/bin/nextclade2 https://github.com/nextstrain/nextclade/releases/latest/download/nextclade-x86_64-unknown-linux-gnu \
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
RUN curl -fsSL -o /final/bin/datasets https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/datasets
RUN curl -fsSL -o /final/bin/dataformat https://ftp.ncbi.nlm.nih.gov/pub/datasets/command-line/v2/linux-amd64/dataformat

# ———————————————————————————————————————————————————————————————————— #

# Build UShER for use with pangolin 4+
FROM debian:bullseye AS usher
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
ENV DEBIAN_FRONTEND=noninteractive
USER root
RUN apt-get update && apt-get install -yq --no-install-recommends \
    git wget \
    ca-certificates \
    sudo python3 python3-pip
RUN mkdir -p /usherbuild
WORKDIR /usherbuild
# faSomeRecords and faSize are needed for the UShER WDL workflow
RUN wget http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/faSomeRecords
RUN wget http://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/faSize
RUN chmod 775 *
## Checkout latest release
RUN git clone https://github.com/yatisht/usher.git
RUN cd usher && git checkout v0.6.0 && ./install/installUbuntu.sh

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
# boost libs: for running Usher
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
        zstd \
        libboost-filesystem1.74.0 \
        libboost-program-options1.74.0 \
        libboost-iostreams1.74.0 \
        libboost-date-time1.74.0 \
        libprotobuf23 \
        libtbb2
# Install a specific Node.js version
# https://github.com/nodesource/distributions/blob/0d81da75/README.md#installation-instructions
RUN curl -fsSL https://deb.nodesource.com/setup_14.x | bash - \
 && apt-get update && apt-get install -y nodejs

# libtbb doesn't install well on bullseye:
RUN ln -s /usr/lib/x86_64-linux-gnu/libtbb.so.2 /usr/lib/x86_64-linux-gnu/libtbb_preview.so.2

# Configure bash for interactive usage
COPY bashrc /etc/bash.bashrc

# Copy binaries
COPY --from=builder /final/bin/ /usr/local/bin/
COPY --from=builder /final/share/ /usr/local/share/
COPY --from=builder /final/libexec/ /usr/local/libexec/
COPY --from=usher \
    /usherbuild/usher/build/compareVCF \
    /usherbuild/usher/build/faToVcf \
    /usherbuild/usher/build/matOptimize \
    /usherbuild/usher/build/matUtils \
    /usherbuild/usher/build/ripples \
    /usherbuild/usher/build/ripples-fast \
    /usherbuild/usher/build/ripplesInit \
    /usherbuild/usher/build/ripplesUtils \
    /usherbuild/usher/build/transpose_vcf \
    /usherbuild/usher/build/transposed_vcf_print_name \
    /usherbuild/usher/build/transposed_vcf_to_fa \
    /usherbuild/usher/build/transposed_vcf_to_vcf \
    /usherbuild/usher/build/usher \
    /usherbuild/usher/build/usher-sampled \
    /usr/local/bin

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
