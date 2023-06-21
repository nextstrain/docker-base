# This is a multi-stage image build.
#
# We first create a "builder" image and then create our final image by copying
# things from the builder image.  The point is to avoid bloating the final
# image with tools only needed during the image build.

# First build the temporary image.
FROM python:3.10-slim-bullseye AS builder

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

RUN mkdir /nextstrain

# ———————————————————————————————————————————————————————————————————— #

# Now build the final image.
FROM python:3.10-slim-bullseye AS final

SHELL ["/bin/bash", "-e", "-u", "-o", "pipefail", "-c"]

# Add Nextstrain components
COPY --from=builder /nextstrain /nextstrain

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
