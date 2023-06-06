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

_You can build this image locally during development, but it's important for
production releases to happen via CI so a complete multi-platform image is
built and validated._

To build this image for local development and testing, run:

    make local-image    # or just: make

This will leave you with a `localhost:5000/nextstrain/base:latest` image loaded
into your local Docker daemon and available to `docker run` commands (and thus
`nextstrain` commands).  Run `make` again to update the image after source
modifications.

Alternatively, you can take the steps yourself,

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

    By default, this builds for a single platform `linux/amd64`, tags the image with `latest`, and pushes to
    `localhost:5000`. See instructions at the top of the script for additional
    options.

    If the target platform is different from the build platform, set up emulation before running `./devel/build`. This can be achieved using [`tonistiigi/binfmt`](https://github.com/tonistiigi/binfmt). For example, to set up emulation for `linux/arm64`, run:

    ```
    docker run --privileged --rm tonistiigi/binfmt --install arm64
    ```

On each subsequent change during your development iterations, you can run just
the `./devel/build` command again.

If you need to force the cached Nextstrain layers to rebuild to, for example,
pick up a new version of augur or auspice, set the `CACHE_DATE` environment
variable to a new timestamp first:

    export CACHE_DATE=$(date --utc +%Y%m%dT%H%M%SZ)

Otherwise, letting the build process use the cached layers will save you time
during development iterations.

### Validate the images

Before using the images, they should be checked for any inconsistencies.

    ./devel/validate-platforms

The output and exit code will tell you whether validation is successful.

### Using the images locally

Since the images are pushed directly to the local registry, they are not
available to the local Docker daemon after building (i.e.
`nextstrain build --image nextstrain/base` does not refer to the latest built
image). To pull the images for local usage, run:

    ./devel/pull-from-registry

When building with `make`, the newly built
`localhost:5000/nextstrain/base:latest` image is automatically made available
for you.  However, the corresponding `base-builder` image is _not_.

### Pushing images to Docker Hub

To push images you've built locally to Docker Hub, you can run:

    ./devel/copy-images -t <tag>

This will copy the `nextstrain/base:<tag>` and `nextstrain/base-builder:<tag>`
images from the local Docker registry to Docker Hub. See instructions at the top
of the script for more options.

### Adding a new software program

To add a software program to `nextstrain/base`, follow steps in this order:

1. Check if it is available via the Ubuntu package manager. You can use
   `apt-cache search` or [Ubuntu Packages Search](https://packages.ubuntu.com/)
   if you do not have an Ubuntu machine. If available, add it to the `apt-get
   install` command following `FROM … AS final`
   ([example](https://github.com/nextstrain/docker-base/commit/8f5e059ce897a85194f35517e56b31424e89472e)).
2. Check if it is available via PyPI. You can search on [PyPI's
   website](https://pypi.org/search/). If available, add an install command to
   the section labeled with `Install programs via pip`.
3. Check if a pre-built binary for the `linux/amd64` platform (name contains
   `linux` and `amd64`/`x86_64`) is available on the software's website (e.g.
   GitHub release assets). If available, add a download command to the section
   labeled with `Download pre-built programs`.
    - If a pre-built binary supporting `linux/arm64` (name contains `linux` and
      `arm64`/`aarch64`) is also available, that should be used conditionally on
      `ARG`s `TARGETPLATFORM` or `TARGETOS`+`TARGETARCH` in the Dockerfile. See
      existing usage of those arguments for examples.
4. The last resort is to build from source. Look for instructions on the
   software's website. Add a build command to the section labeled with `Build
   programs from source`. Note that this can require platform-specific
   instructions.

If possible, pin the software to a specific version. Otherwise, add the
download/install/build command to the section labeled with `Add unpinned
programs` to ensure the latest version is included in every Docker image build.

### Best practices

The smaller the image size, the better.  To this end we build upon a ["slim"
Python image][] and use a [multi-stage build][] where only _artifacts_ are
included in the final image without any of the software required only for
compiling, installing, building, etc.

Try to follow [Docker best practices][] for images, although not all apply to our
use case, which is somewhat atypical.

The [Dockerfile reference documentation][] is quite handy for looking up the
details of each Dockerfile command (`COPY`, `ADD`, etc).

Use `bash` as the default shell for all stages in the Dockerfile to use handy
modern shell features.

Run bash scripts and Dockerfile commands with the `-euo pipefail` options for
proper error handling. That is, these options should be set at the start of each
script and build stage in the Dockerfile.

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
