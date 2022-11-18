# Docker image for nextstrain/base

This is the source for creating the `nextstrain/base` Docker image.  Currently
the image is published as [`nextstrain/base`][].

Ideally most pathogen builds are supported by this base image without further
customization.  The possibility remains, however, for pathogens to define and
use an image derived from this base layer.  This would be desirable for
pathogen builds requiring custom external software, like Python modules or
tree-builders.

The image includes the standard Nextstrain components Fauna, Augur, and Auspice,
as well as other bioinformatics tools like MAFFT, RAxML, FastTree, IQ-TREE, and
TreeTime.

This image is best interacted with using the [Nextstrain command-line
tool][nextstrain-cli].

[nextstrain-cli]: https://github.com/nextstrain/cli


## Developing

### Rebuilding an image and pushing to Docker Hub

To rebuild the image with the latest versions of its software and push to Docker Hub, go to [the GitHub Actions workflow](https://github.com/nextstrain/docker-base/actions/workflows/ci.yml), select **Run workflow**, and confirm.
This is most helpful when you want the image to contain the latest version of a tool whose release does not automatically trigger a new build of the image and you do not need to modify the `Dockerfile`.

### Building

To build this image locally,

1. Start a local Docker registry.

    ```
    ./devel/start-localhost-registry
    ```

    It will be served at `localhost:5000`. Optionally, specify another port as
    an argument. Running a local Docker registry allows us to mimic direct push
    to a registry done in the GitHub Actions CI workflow.

2. Build the image.

    ```
    ./devel/build
    ```

    By default, this tags the image with `latest` and pushes to
    `localhost:5000`. See instructions at the top of the script for additional
    options.

On each subsequent change during your development iterations, you can run just
the `./devel/build` command again.

If you need to force the cached Nextstrain layers to rebuild to, for example,
pick up a new version of augur or auspice, set the `CACHE_DATE` environment
variable to a new timestamp first:

    export CACHE_DATE=$(date --utc +%Y%m%dT%H%M%SZ)

Otherwise, letting the build process use the cached layers will save you time
during development iterations.

### Pushing images to Docker Hub

To push images you've built locally to Docker Hub, you can run:

    ./devel/copy-images -t <tag>

This will copy the `nextstrain/base:<tag>` and `nextstrain/base-builder:<tag>`
images from the local Docker registry to Docker Hub. See instructions at the top
of the script for more options.

### Best practices

The smaller the image size, the better.  To this end we build upon a ["slim"
Python image][] and use a [multi-stage build][] where only _artifacts_ are
included in the final image without any of the software required only for
compiling, installing, building, etc.

Try to follow [Docker best practices][] for images, although not all apply to our
use case, which is somewhat atypical.

The [Dockerfile reference documentation][] is quite handy for looking up the
details of each Dockerfile command (`COPY`, `ADD`, etc).

### Continuous integration

Every push to this repository triggers a new build of the image [a GitHub Actions workflow][].  This helps ensure the image builds successfully with the new commits.

Images built from the `master` branch are additionally pushed to the [Docker
registry][`nextstrain/base`].  The build instructions used by the workflow are in
this repo's `.github/workflows/ci.yml`.


[`nextstrain/base`]: https://hub.docker.com/r/nextstrain/base/
["slim" Python image]: https://hub.docker.com/_/python
[multi-stage build]: https://docs.docker.com/develop/develop-images/multistage-build/
[Docker best practices]: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
[Dockerfile reference documentation]: https://docs.docker.com/engine/reference/builder/
[GitHub Actions]: https://github.com/nextstrain/docker-base/actions/workflows/ci.yml
