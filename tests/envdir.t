#!/usr/bin/env cram

Setup.

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

  $ mkdir env.d
  $ chmod a+rx env.d
  $ echo AAAA     > env.d/a
  $ echo BB BB BB > env.d/b
  $ touch           env.d/z

Bind-mounted env.d.

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d "$IMAGE" \
  >   bash -eu -c 'echo "$a"'
  AAAA

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d "$IMAGE" \
  >   bash -eu -c 'echo "$b"'
  BB BB BB

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d "$IMAGE" \
  >   bash -eu -c 'echo "$z"'
  bash: line 1: z: unbound variable
  [1]

Works with externally-set user/group.

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'echo "$a"'
  AAAA

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'echo "$b"'
  BB BB BB

  $ docker run --rm -v "$PWD"/env.d:/nextstrain/env.d -u 1234:5678 "$IMAGE" \
  >   bash -eu -c 'echo "$z"'
  bash: line 1: z: unbound variable
  [1]

Files are removed with NEXTSTRAIN_DELETE_ENVD=1.

  $ ls -1 env.d
  a
  b
  z

  $ docker run --rm -e NEXTSTRAIN_DELETE_ENVD=1 -v "$PWD"/env.d:/nextstrain/env.d -u "$(id -u):$(id -g)" "$IMAGE" \
  >   bash -eu -c 'echo "$a"; echo "$b"; ls -1 /nextstrain/env.d'
  AAAA
  BB BB BB

  $ ls -1 env.d
