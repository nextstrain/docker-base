#!/usr/bin/env cram

Setup.

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

A workdir URL is required and not setting one here causes the entrypoint to
error, but that's enough for testing verbose mode.

  $ export NEXTSTRAIN_AWS_BATCH_WORKDIR_URL=

Verbose mode is default.

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_WORKDIR_URL "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true
  + case "$NEXTSTRAIN_AWS_BATCH_WORKDIR_URL" in
  + echo 'entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>'
  entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>
  + exit 1
  [1]

Verbose mode is anything not zero.

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE=yes} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true
  + case "$NEXTSTRAIN_AWS_BATCH_WORKDIR_URL" in
  + echo 'entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>'
  entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>
  + exit 1
  [1]

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE=} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true
  + case "$NEXTSTRAIN_AWS_BATCH_WORKDIR_URL" in
  + echo 'entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>'
  entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>
  + exit 1
  [1]

Verbose mode can be turned off.

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE=0} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true
  entrypoint-aws-batch: No handler for NEXTSTRAIN_AWS_BATCH_WORKDIR_URL <>
  [1]
