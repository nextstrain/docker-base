Run the zika tutorial.

  $ curl -fsSL https://api.github.com/repos/nextstrain/zika-tutorial/tarball/HEAD \
  > | tar xzvpf - --no-same-owner --strip-components=1 > /dev/null
  $ nextstrain build --ambient . --forceall --quiet all
