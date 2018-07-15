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
        build-base \
        ca-certificates \
        curl \
        freetype-dev \
        git \
        gmp-dev \
        libpng-dev \
        nodejs \
        nodejs-npm \
        python{2,3}-dev \
        py2-{pip,setuptools} \
        suitesparse-dev


# mafft
WORKDIR /build/mafft
RUN curl -fsSL https://mafft.cbrc.jp/alignment/software/mafft-7.402-linux.tgz \
  | tar xzvpf - --strip-components=2 mafft-linux64/mafftdir/

# RAxML
WORKDIR /build/RAxML
RUN curl -fsSL https://api.github.com/repos/stamatak/standard-RAxML/tarball/master \
  | tar xzvpf - --strip-components=1
RUN make -f Makefile.AVX.PTHREADS.gcc   # AVX should be widely-supported enough

# FastTree
WORKDIR /build/FastTree
RUN curl -fsSL https://api.github.com/repos/tsibley/FastTree/tarball/master \
  | tar xzvpf - --strip-components=1
RUN make FastTreeDblMP

# IQ-TREE
WORKDIR /build/IQ-TREE
RUN curl -fsSL https://github.com/Cibiv/IQ-TREE/releases/download/v1.6.5/iqtree-1.6.5-Linux.tar.gz \
  | tar xzvpf - --strip-components=1

# Install Python 2 depedencies
# May be upgraded by augur/requirements.txt
RUN CVXOPT_BLAS_LIB=openblas \
    CVXOPT_LAPACK_LIB=openblas \
        pip2 install --global-option=build_ext \
            --global-option="-I/usr/include/suitesparse" \
            cvxopt==1.1.9

RUN pip2 install biopython==1.69
RUN pip2 install boto==2.38
RUN pip2 install future==0.16.0
RUN pip2 install GitPython==2.1.10
RUN pip2 install ipdb==0.10.1
RUN pip2 install matplotlib==2.2.2
RUN pip2 install pandas==0.17.1
RUN pip2 install pytest==3.2.1
RUN pip2 install seaborn==0.6.0

# Install Python 3 dependencies
# May be upgraded by augur/setup.py

# cvxopt is an dep we explicitly pre-install because it is particularly fussy.
# It is separated out from the rest of the installs to ensures that pip wheels
# can be used for as much as possible, since using --global-option disables use
# of wheels.
RUN CVXOPT_BLAS_LIB=openblas \
    CVXOPT_LAPACK_LIB=openblas \
        pip3 install --global-option=build_ext \
            --global-option="-I/usr/include/suitesparse" \
            cvxopt==1.1.9
RUN pip3 install bcbio-gff==0.6.4
RUN pip3 install biopython==1.69
RUN pip3 install boto==2.38
RUN pip3 install ipdb==0.10.1
RUN pip3 install matplotlib==2.2.2
RUN pip3 install pandas==0.17.1
RUN pip3 install seaborn==0.6.0
RUN pip3 install snakemake==5.1.5

# Add Nextstrain components
#
# sacra
WORKDIR /nextstrain/sacra

RUN curl -fsSL https://api.github.com/repos/nextstrain/sacra/tarball/master \
  | tar xzvpf - --strip-components=1

# fauna
WORKDIR /nextstrain/fauna

RUN curl -fsSL https://api.github.com/repos/nextstrain/fauna/tarball/master \
  | tar xzvpf - --strip-components=1

# augur
WORKDIR /nextstrain/augur

RUN curl -fsSL https://api.github.com/repos/nextstrain/augur/tarball/master \
  | tar xzvpf - --strip-components=1

# auspice
WORKDIR /nextstrain/auspice

RUN curl -fsSL https://api.github.com/repos/nextstrain/auspice/tarball/master \
  | tar xzvpf - --strip-components=1


# Install Python 2 deps
RUN pip2 install --requirement=/nextstrain/{sacra,fauna}/requirements.txt

# Install Python 3 deps
RUN pip3 install --process-dependency-links /nextstrain/augur

# …but remove global augur install.  We'll later install a tiny wrapper in
# /usr/bin/augur that runs out of /nextstrain/augur, which makes replacing the
# augur version in development as easy as --volume .../augur:/nextstrain/augur.
#
# Note that we only have to install augur (above) and then uninstall it because
# there's not an --only-deps option to pip that we can use in the previous RUN.
RUN pip3 uninstall --yes --verbose augur

# Install Node deps
RUN cd /nextstrain/auspice && npm install

# Install envdir, which is used by pathogen builds
RUN pip3 install envdir


# ———————————————————————————————————————————————————————————————————— #


# Now build the final image.
FROM alpine:3.7

# Add system runtime deps
RUN apk add --no-cache \
        ca-certificates \
        bash \
        freetype \
        gmp \
        lapack \
        libpng \
        nodejs \
        python2 \
        python3 \
        suitesparse

# Add custom built programs
ENV MAFFT_BINARIES=/usr/local/libexec
COPY --from=builder /build/mafft/bin/     /usr/local/bin/
COPY --from=builder /build/mafft/libexec/ /usr/local/libexec/
COPY --from=builder \
    /build/RAxML/raxmlHPC-PTHREADS-AVX \
    /build/FastTree/FastTreeDblMP \
    /build/IQ-TREE/bin/iqtree \
    /usr/local/bin/

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
    /usr/bin/snakemake \
    /usr/bin/

# Add Nextstrain components
COPY --from=builder /nextstrain /nextstrain

# Add tiny augur wrapper to run augur from /nextstrain/augur
COPY augur-wrapper /usr/local/bin/augur
RUN chmod a+rx /usr/local/bin/augur

# Add tiny auspice wrapper to run auspice's local dev server from /nextstrain/auspice
COPY auspice-wrapper /usr/local/bin/auspice
RUN chmod a+rx /usr/local/bin/auspice

# Add our entrypoint
COPY entrypoint /sbin/entrypoint
RUN chmod a+rx /sbin/entrypoint

# The host should bind mount the pathogen build dir into /nextstrain/build.
WORKDIR /nextstrain/build

ENTRYPOINT ["/sbin/entrypoint"]
