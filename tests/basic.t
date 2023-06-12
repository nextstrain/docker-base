#!/usr/bin/env cram

Setup.

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

Default working directory.

  $ docker run --rm "$IMAGE" pwd
  /nextstrain/build

Default home directory.

  $ docker run --rm "$IMAGE" env | grep ^HOME=
  HOME=/nextstrain

Drops default root privileges.

  $ docker run --rm "$IMAGE" id
  uid=*(nextstrain) gid=*(nextstrain) groups=*(nextstrain) (glob)

Respects externally-set user/group.

  $ docker run --rm --user 1234:5678 "$IMAGE" id
  uid=1234 gid=5678 groups=5678

/nextstrain has open, /tmp-like permissions.

  $ docker run --rm "$IMAGE" ls -ld /nextstrain
  drwxrwxrwt * /nextstrain (glob)

/nextstrain/build is writable by default nextstrain user.

  $ docker run --rm "$IMAGE" touch /nextstrain/build/test
