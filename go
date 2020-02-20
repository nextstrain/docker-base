#!/bin/bash
set -euo pipefail
folder=../zika-tutorial/

pushd $folder
rm -rf .dat
dat create --yes .
pub=$(dat keys)
pri=$(dat keys export)
dat sync &
popd

#docker run --rm -it -e NEXTSTRAIN_AWS_BATCH_WORKDIR_URL=$pub -e NEXTSTRAIN_AWS_BATCH_WORKDIR_SECRET_KEY=$pri --entrypoint /sbin/entrypoint-aws-batch nextstrain/base bash -c 'echo hi > hello-world'
