#!/usr/bin/env cram

Setup.

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

NEXTSTRAIN_WORKDIR changes initial working directory.

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/augur "$IMAGE" \
  >   bash -eu -c 'echo "$PWD"'
  /nextstrain/augur

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/augur -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'echo "$PWD"'
  /nextstrain/augur

Missing directories are created, like with the `--workdir` option of `docker run`.

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/a/b/c "$IMAGE" \
  >   bash -eu -c 'ls -ld "$PWD"'
  drwxr-xr-x * nextstrain nextstrain * /nextstrain/a/b/c (glob)

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/a/b/c -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'ls -ld "$PWD"'
  drwxr-xr-x * 1234 5678 * /nextstrain/a/b/c (glob)

…but permissions still apply, as the `mkdir` happens after drop-privs.

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nope "$IMAGE" \
  >   bash -eu -c 'echo "$PWD"'
  mkdir: cannot create directory ‘/nope’: Permission denied
  [1]

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nope -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'echo "$PWD"'
  mkdir: cannot create directory ‘/nope’: Permission denied
  [1]
