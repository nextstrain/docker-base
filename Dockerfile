# This is a multi-stage image build.
#
# We first create a "builder" image and then create our final image by copying
# things from the builder image.  The point is to avoid bloating the final
# image with tools only needed during the image build.

# First build the temporary image.
FROM alpine:3.7 AS builder

# Execute subsequent RUN statements with bash for handy modern shell features.
RUN apk add --no-cache bash
SHELL ["/bin/bash", "-c"]

# Add system deps for building
RUN apk add --no-cache \
        autoconf \
        automake \
        build-base \
        ca-certificates \
        curl \
        freetype-dev \
        git \
        gmp-dev \
        libpng-dev \
        linux-headers \
        nodejs \
        nodejs-npm \
        perl \
        python{2,3}-dev \
        py2-{pip,setuptools} \
        suitesparse-dev

# Downloading dependencies, these should be pinned to specific versions

# mafft
WORKDIR /build/mafft
RUN curl -fsSL https://mafft.cbrc.jp/alignment/software/mafft-7.402-linux.tgz \
  | tar xzvpf - --strip-components=2 mafft-linux64/mafftdir/

# RAxML
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/stamatak/standard-RAxML/tarball/v8.2.12 \
  | tar xzvpf - --strip-components=1
RUN make -f Makefile.AVX.PTHREADS.gcc   # AVX should be widely-supported enough

# FastTree
WORKDIR /build/FastTree
RUN curl -fsSL https://api.github.com/repos/tsibley/FastTree/tarball/50c5b098ea085b46de30bfc29da5e3f113353e6f \
  | tar xzvpf - --strip-components=1
RUN make FastTreeDblMP

# IQ-TREE
WORKDIR /build/IQ-TREE
RUN curl -fsSL https://github.com/Cibiv/IQ-TREE/releases/download/v1.6.6/iqtree-1.6.6-Linux.tar.gz \
  | tar xzvpf - --strip-components=1

# vcftools
WORKDIR /build/vcftools
RUN curl -fsSL https://github.com/vcftools/vcftools/releases/download/v0.1.15/vcftools-0.1.15.tar.gz \
  | tar xzvpf - --strip-components=2
RUN ./configure --prefix=$PWD/built && make && make install

# Install Python 2 dependencies
# These may be upgraded by sacra/requirements.txt or fauna/requirements.txt
# but having them here enables caching

RUN pip2 install biopython==1.73
RUN pip2 install boto==2.38
RUN pip2 install pandas==0.23.4
RUN pip2 install requests==2.20.0
RUN pip2 install rethinkdb==2.3.0.post6
RUN pip2 install unidecode==1.0.22
RUN pip2 install xlrd==1.0.0

# Install Python 3 dependencies
# These may be upgraded by augur/setup.py,
# but having them here enables caching

# cvxopt install is particularly fussy.
# It is separated out from the rest of the installs to ensures that pip wheels
# can be used for as much as possible, since using --global-option disables use
# of wheels.
RUN CVXOPT_BLAS_LIB=openblas \
  CVXOPT_LAPACK_LIB=openblas \
    pip3 install --global-option=build_ext \
      --global-option="-I/usr/include/suitesparse" \
      cvxopt==1.1.9
RUN pip3 install bcbio-gff==0.6.6
RUN pip3 install biopython==1.74
RUN pip3 install boto==2.38
RUN pip3 install ipdb==0.10.1
RUN pip3 install jsonschema==3.0.1
RUN pip3 install matplotlib==2.2.2
RUN pip3 install pandas==0.23.4
RUN pip3 install phylo-treetime==0.6.4
RUN pip3 install requests==2.20.0
RUN pip3 install rethinkdb==2.3.0.post6
RUN pip3 install seaborn==0.9.0
RUN pip3 install snakemake==5.8.1
RUN pip3 install unidecode==1.0.22
RUN pip3 install xlrd==1.0.0

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir

# Install tooling for our AWS Batch builds, which use `aws s3`.
RUN pip3 install awscli

# Install our own CLI so builds can do things like `nextstrain deploy`
RUN pip3 install nextstrain-cli

# Add Nextstrain components

# Allow caching to be avoided from here on out by calling
# docker build --build-arg CACHE_DATE="$(date)"
ARG CACHE_DATE

# Add download helper
COPY devel/download-repo /devel/

# sacra
RUN /devel/download-repo https://github.com/nextstrain/sacra master /nextstrain/sacra

# fauna
RUN /devel/download-repo https://github.com/nextstrain/fauna master /nextstrain/fauna

# augur
RUN /devel/download-repo https://github.com/nextstrain/augur release /nextstrain/augur

# auspice
RUN /devel/download-repo https://github.com/nextstrain/auspice release /nextstrain/auspice


# Install Python 2 deps
RUN pip2 install --requirement=/nextstrain/sacra/requirements.txt
RUN pip2 install --requirement=/nextstrain/fauna/requirements.txt

# Install Python 3 deps
RUN pip3 install --requirement=/nextstrain/fauna/requirements.txt

# Augur is an editable install so we can overlay the augur version in the image
# with --volume=.../augur:/nextstrain/augur and still have it globally
# accessible and importable.
RUN pip3 install --editable /nextstrain/augur

# Install Node deps, build Auspice, and link it into the global search path.  A
# fresh install is only ~40 seconds, so we're not worrying about caching these
# as we did the Python deps.  Building auspice means we can run it without
# hot-reloading, which is time-consuming and generally unnecessary in the
# container image.  Linking is equivalent to an editable Python install and
# used for the same reasons described above.
RUN cd /nextstrain/auspice && npm install && npm run build && npm link


# ———————————————————————————————————————————————————————————————————— #


# Now build the final image.
FROM alpine:3.7

# Add system runtime deps
RUN apk add --no-cache \
        ca-certificates \
        curl \
        bash \
        freetype \
        gmp \
        gzip \
        lapack \
        libpng \
        nodejs \
        perl \
        python2 \
        python3 \
        suitesparse \
        ruby \
        tar \
        wget \
        zip unzip

# Configure the prompt for interactive usage
COPY prompt.sh /etc/profile.d/

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

# Ensure all container users can execute these programs
RUN chmod a+rX /usr/local/bin/* /usr/local/libexec/*

# Add installed Python libs
COPY --from=builder /usr/lib/python2.7/site-packages/ /usr/lib/python2.7/site-packages/
COPY --from=builder /usr/lib/python3.6/site-packages/ /usr/lib/python3.6/site-packages/

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
    /usr/bin/augur \
    /usr/bin/aws \
    /usr/bin/nextstrain \
    /usr/bin/snakemake \
    /usr/bin/

# Add installed Node libs
COPY --from=builder /usr/lib/node_modules/ /usr/lib/node_modules/

# Add globally linked Auspice script.
#
# This symlink is present in the "builder" image, but using COPY results in the
# _contents_ of the target being copied instead of a symlink being created.
# The symlink is required so that Auspice's locally-installed deps are
# correctly discovered by node.
RUN ln -sv /usr/lib/node_modules/auspice/auspice.js /usr/bin/auspice

# Add Nextstrain components
COPY --from=builder /nextstrain /nextstrain

# Add our entrypoints
COPY entrypoint entrypoint-aws-batch /sbin/
RUN chmod a+rx /sbin/entrypoint*

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
