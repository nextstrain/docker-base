# Docker image for nextstrain/base

This is the source for creating the `nextstrain/base` Docker image.  Currently
the image is published as [`nextstrain/base`][].

Ideally most pathogen builds are supported by this base image without further
customization.  The possibility remains, however, for pathogens to define and
use an image derived from this base layer.  This would be desirable for
pathogen builds requiring custom external software, like Python modules or
tree-builders.

The image includes the standard Nextstrain components sacra, fauna, augur
(modular), and auspice, as well as other bioinformatics tools like mafft,
RAxML, FastTree, IQ-TREE, and TreeTime.

This image is best interacted with using the [nextstrain command-line
tool][nextstrain-cli].

[nextstrain-cli]: https://github.com/nextstrain/cli


## Developing

### Building

To build this image locally, you can run the following from within this repo:

    docker build .

If you need to force cached layers to rebuild, pass the `--no-cache` option.
Otherwise, cached layers will save you time during development iterations.

### Best practices

The smaller the image size, the better.  To this end we build upon an [Alpine
Linux][] image (instead of Ubuntu) and use a [multi-stage build][] where only
_artifacts_ are included in the final image without any of the software
required only for compiling, installing, building, etc.  The [Alpine Linux
package index][] is useful for finding what's installable through its package
manager `apk`.

Try to follow [Docker best practices][] for images, although not all apply to our
use case, which is somewhat atypical.

The [Dockerfile reference documentation][] is quite handy for looking up the
details of each Dockerfile command (`COPY`, `ADD`, etc).

[`nextstrain/base`]: https://hub.docker.com/r/nextstrain/base/
[Alpine Linux]: https://alpinelinux.org
[Alpine Linux package index]: https://pkgs.alpinelinux.org/packages?branch=v3.7&repo=main&arch=x86_64
[multi-stage build]: https://docs.docker.com/develop/develop-images/multistage-build/
[Docker best practices]: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
[Dockerfile reference documentation]: https://docs.docker.com/engine/reference/builder/
