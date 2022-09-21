# This is a multi-stage image build.
#
# We first create a "builder" image and then create our final image by copying
# things from the builder image.  The point is to avoid bloating the final
# image with tools only needed during the image build.

# First build the temporary image.
FROM python:3.7-slim-buster AS builder

# Execute subsequent RUN statements with bash for handy modern shell features.
SHELL ["/bin/bash", "-c"]

# Add system deps for building
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        libgmp-dev \
        libpng-dev \
        nodejs \
        npm \
        pkg-config

# Downloading dependencies, these should be pinned to specific versions

# mafft
WORKDIR /build/mafft
RUN curl -fsSL https://mafft.cbrc.jp/alignment/software/mafft-7.475-linux.tgz \
  | tar xzvpf - --no-same-owner --strip-components=2 mafft-linux64/mafftdir/

# RAxML
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/stamatak/standard-RAxML/tarball/v8.2.12 \
  | tar xzvpf - --no-same-owner --strip-components=1
RUN make -f Makefile.AVX.PTHREADS.gcc   # AVX should be widely-supported enough

# FastTree
WORKDIR /build/FastTree
RUN curl -fsSL https://api.github.com/repos/tsibley/FastTree/tarball/50c5b098ea085b46de30bfc29da5e3f113353e6f \
  | tar xzvpf - --no-same-owner --strip-components=1
RUN make FastTreeDblMP

# IQ-TREE
WORKDIR /build/IQ-TREE
RUN curl -fsSL https://github.com/iqtree/iqtree2/releases/download/v2.1.2/iqtree-2.1.2-Linux.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=1
RUN mv bin/iqtree2 bin/iqtree

# vcftools
WORKDIR /build/vcftools
RUN curl -fsSL https://github.com/vcftools/vcftools/releases/download/v0.1.16/vcftools-0.1.16.tar.gz \
  | tar xzvpf - --no-same-owner --strip-components=2
RUN ./configure --prefix=$PWD/built && make && make install

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir==1.0.1

# Install tooling for our AWS Batch builds, which use `aws s3`.
RUN pip3 install awscli==1.18.195

# Install our own CLI so builds can do things like `nextstrain deploy`
RUN pip3 install nextstrain-cli==2.0.0.post1

# Install Snakemake and related optional dependencies.
RUN pip3 install snakemake==5.10.0
# Google Cloud Storage package is required for Snakemake to fetch remote files
# from Google Storage URIs.
RUN pip3 install google-cloud-storage==2.1.0

# Add Nextstrain components

# Allow caching to be avoided from here on out by calling
# docker build --build-arg CACHE_DATE="$(date)"
ARG CACHE_DATE

# Add helpers for build
COPY devel/download-repo devel/latest-augur-release-tag /devel/

# Fauna
RUN /devel/download-repo https://github.com/nextstrain/fauna master /nextstrain/fauna

# Augur
RUN /devel/download-repo https://github.com/nextstrain/augur "$(/devel/latest-augur-release-tag)" /nextstrain/augur

# Auspice
RUN /devel/download-repo https://github.com/nextstrain/auspice release /nextstrain/auspice

# Install Fauna deps
RUN pip3 install --requirement=/nextstrain/fauna/requirements.txt

# Augur is an editable install so we can overlay the augur version in the image
# with --volume=.../augur:/nextstrain/augur and still have it globally
# accessible and importable.
RUN pip3 install --editable "/nextstrain/augur"

# Install pathogen-specific workflow dependencies. Since we only maintain a
# single Docker image to support all pathogen workflows, some pathogen-specific
# functionality must live in this Dockerfile. The following dependencies may be
# used by multiple pathogen workflows, but they have been commented according to
# the original pathogen that added these dependencies.

# ncov
RUN pip3 install epiweeks==2.1.2

# Add Pangolin and PangoLEARN + deps
RUN curl -fsSL https://github.com/virus-evolution/gofasta/releases/download/v0.0.6/gofasta-linux-amd64 \
        -o /usr/local/bin/gofasta \
  && chmod a+rx /usr/local/bin/gofasta
RUN cd /usr/local/bin && curl -fsSL https://github.com/lh3/minimap2/releases/download/v2.24/minimap2-2.24_x64-linux.tar.bz2 \
  | tar xjvpf - --no-same-owner --strip-components=1 minimap2-2.24_x64-linux/minimap2
RUN pip install pysam
RUN pip install git+https://github.com/cov-lineages/pangolin.git@v3.1.17
RUN pip install git+https://github.com/cov-lineages/pangoLEARN.git@2021-12-06
RUN pip install git+https://github.com/cov-lineages/scorpio.git@v0.3.16
RUN pip install git+https://github.com/cov-lineages/constellations.git@v0.1.1
RUN pip install git+https://github.com/cov-lineages/pango-designation.git@19d9a537b9

# Install Node deps, build Auspice, and link it into the global search path.  A
# fresh install is only ~40 seconds, so we're not worrying about caching these
# as we did the Python deps.  Building auspice means we can run it without
# hot-reloading, which is time-consuming and generally unnecessary in the
# container image.  Linking is equivalent to an editable Python install and
# used for the same reasons described above.
RUN cd /nextstrain/auspice && npm update && npm install && npm run build && npm link

# ———————————————————————————————————————————————————————————————————— #

# Now build the final image.
FROM python:3.7-slim-buster

# Add system runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        curl \
        gzip \
        jq \
        less \
        nodejs \
        perl \
        ruby \
        wget \
        xz-utils \
        zip unzip \
        zstd

# Configure bash for interactive usage
COPY bashrc /etc/bash.bashrc

# Add custom built programs
ENV MAFFT_BINARIES=/usr/local/libexec
COPY --from=builder /build/mafft/bin/     /usr/local/bin/
COPY --from=builder /build/mafft/libexec/ /usr/local/libexec/
COPY --from=builder \
    /build/RAxML/raxmlHPC-PTHREADS-AVX \
    /build/FastTree/FastTreeDblMP \
    /build/IQ-TREE/bin/iqtree \
    /usr/local/bin/

COPY --from=builder /build/vcftools/built/bin/    /usr/local/bin/
COPY --from=builder /build/vcftools/built/share/  /usr/local/share/

# Add Nextalign v2
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/latest/download/nextalign-x86_64-unknown-linux-gnu \
      --output /usr/local/bin/nextalign2 \
 && chmod a+rx /usr/local/bin/nextalign2

# Add Nextclade v2
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/latest/download/nextclade-x86_64-unknown-linux-gnu \
      --output /usr/local/bin/nextclade2 \
 && chmod a+rx /usr/local/bin/nextclade2

# Add Nextalign v1
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextalign-Linux-x86_64 \
      --output /usr/local/bin/nextalign1 \
 && chmod a+rx /usr/local/bin/nextalign1

# Add Nextclade v1
RUN curl -fsSL https://github.com/nextstrain/nextclade/releases/download/1.11.0/nextclade-Linux-x86_64 \
      --output /usr/local/bin/nextclade1 \
 && chmod a+rx /usr/local/bin/nextclade1

# Set default Nextclade and Nextalign version to 2
RUN ln -sv nextclade2 /usr/local/bin/nextclade \
 && ln -sv nextalign2 /usr/local/bin/nextalign

# Add tsv-utils
RUN curl -L -o tsv-utils.tar.gz https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz \
 && tar -x --no-same-owner -v -C /usr/local/bin -z --strip-components 2 --wildcards -f tsv-utils.tar.gz "*/bin/*" \
 && rm -f tsv-utils.tar.gz

# Add csvtk
RUN curl -L https://github.com/shenwei356/csvtk/releases/download/v0.24.0/csvtk_linux_amd64.tar.gz | tar xz --no-same-owner -C /usr/local/bin

# Add seqkit
RUN curl -L https://github.com/shenwei356/seqkit/releases/download/v2.2.0/seqkit_linux_amd64.tar.gz | tar xz --no-same-owner -C /usr/local/bin

# Ensure all container users can execute these programs
RUN chmod a+rX /usr/local/bin/* /usr/local/libexec/*

# Add installed Python libs
COPY --from=builder /usr/local/lib/python3.7/site-packages/ /usr/local/lib/python3.7/site-packages/

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
    /usr/local/bin/gofasta \
    /usr/local/bin/minimap2 \
    /usr/local/bin/nextstrain \
    /usr/local/bin/pangolin \
    /usr/local/bin/pangolearn.smk \
    /usr/local/bin/scorpio \
    /usr/local/bin/snakemake \
    /usr/local/bin/

# Add installed Node libs
COPY --from=builder /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

# Add globally linked Auspice script.
#
# This symlink is present in the "builder" image, but using COPY results in the
# _contents_ of the target being copied instead of a symlink being created.
# The symlink is required so that Auspice's locally-installed deps are
# correctly discovered by node.
RUN ln -sv /usr/local/lib/node_modules/auspice/auspice.js /usr/local/bin/auspice

# Add Nextstrain components
COPY --from=builder /nextstrain /nextstrain

# Add our entrypoints
COPY entrypoint entrypoint-aws-batch /sbin/
RUN chmod a+rx /sbin/entrypoint*

# Make /nextstrain a global HOME, writable by any UID (like /tmp)
RUN chmod a+rwXt /nextstrain
ENV HOME=/nextstrain

# Setup a non-root user for normal operations
RUN useradd nextstrain \
    --system \
    --user-group \
    --shell /bin/bash \
    --home-dir /nextstrain \
    --no-log-init
USER nextstrain:nextstrain

# The host should bind mount the pathogen build dir into /nextstrain/build.
WORKDIR /nextstrain/build

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
