#!/usr/bin/env cram

Setup.

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

  $ export NEXTSTRAIN_AWS_BATCH_VERBOSE=1

--endpoint-url is used when AWS_ENDPOINT_URL is available.

  $ export NEXTSTRAIN_AWS_BATCH_WORKDIR_URL="s3://dummy-value/dummy-value.zip"
  $ export AWS_ENDPOINT_URL="https://custom-endpoint.example.com"

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} --env=AWS_ENDPOINT_URL "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true 2>&1 | grep --only-matching 'aws s3 cp --endpoint-url [^ ]*'
  aws s3 cp --endpoint-url https://custom-endpoint.example.com

--endpoint-url is not used when AWS_ENDPOINT_URL is unavailable.

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch true 2>&1 | grep --only-matching 'aws s3 cp --no-progress [^ ]*'
  aws s3 cp --no-progress s3://dummy-value/dummy-value.zip
