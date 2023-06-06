#!/usr/bin/env cram

Setup.

  $ [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]] || exit 80

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

  $ mkdir env.d
  $ chmod a+rx env.d
  $ echo AAAA     > env.d/a
  $ echo BB BB BB > env.d/b
  $ touch           env.d/z

Files are populated from NEXTSTRAIN_ENVD_URL.

  $ zip --junk-paths env.d{.zip,/*}
    adding: a (*) (glob)
    adding: b (*) (glob)
    adding: z (*) (glob)

  $ export NEXTSTRAIN_ENVD_URL="s3://nextstrain-tmp/$(python3 -c 'import uuid; print(uuid.uuid4())').zip"

  $ aws s3 cp --quiet env.d.zip "$NEXTSTRAIN_ENVD_URL"

  $ docker run --rm -e NEXTSTRAIN_ENVD_URL -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY "$IMAGE" \
  >   bash -eu -c 'echo "$a"; echo "$b"'
  download: s3://nextstrain-tmp/*.zip to ../env.d.zip (glob)
  Archive:  /nextstrain/env.d.zip
   extracting: /nextstrain/env.d/a     
    inflating: /nextstrain/env.d/b     
   extracting: /nextstrain/env.d/z     
  removed '/nextstrain/env.d.zip'
  AAAA
  BB BB BB

Files and NEXTSTRAIN_ENVD_URL are removed with NEXTSTRAIN_DELETE_ENVD=1.

  $ docker run --rm -e NEXTSTRAIN_DELETE_ENVD=1 -e NEXTSTRAIN_ENVD_URL -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY "$IMAGE" \
  >   bash -eu -c 'echo "$a"; echo "$b"; ls -1 /nextstrain/env.d'
  download: s3://nextstrain-tmp/*.zip to ../env.d.zip (glob)
  Archive:  /nextstrain/env.d.zip
   extracting: /nextstrain/env.d/a     
    inflating: /nextstrain/env.d/b     
   extracting: /nextstrain/env.d/z     
  removed '/nextstrain/env.d.zip'
  delete: s3://nextstrain-tmp/*.zip (glob)
  AAAA
  BB BB BB

  $ aws s3 ls "$NEXTSTRAIN_ENVD_URL"
  [1]
