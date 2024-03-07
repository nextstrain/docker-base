Use the image built **for this branch** in Nextstrain CLI:

    NEXTSTRAIN_DOCKER_IMAGE=docker.io/nextstrain/base:${TAG}

Note that this isn't always the image built for this CI run, as it will be
updated on new pushes to the branch.

<!---
TODO: Add instructions to use image built for this specific CI run. Not trivial
since it requires getting the SHA for each platform variant. Something like
this gets that info but is hacky:

    image=nextstrain/base
    tag=latest
    token=$(curl --silent "https://auth.docker.io/token?scope=repository:$image:pull&service=registry.docker.io"  | jq -r '.token')
    curl -s --header "Accept: application/vnd.docker.distribution.manifest.list.v2+json" --header "Authorization: Bearer ${token}" "https://registry-1.docker.io/v2/$image/manifests/$tag" | jq -r '.manifests|.[]| "\(.digest) \(.platform.architecture) \(.platform.variant)"'

--->