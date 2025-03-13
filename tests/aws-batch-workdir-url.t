#!/usr/bin/env cram

Setup.

  $ [[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" ]] || exit 80

  $ : "${IMAGE:=localhost:5000/nextstrain/base:latest}"
  $ (docker image inspect "$IMAGE" || docker image pull "$IMAGE") &>/dev/null

  $ export NEXTSTRAIN_AWS_BATCH_VERBOSE=0

Workdir ZIP archive is downloaded and extracted.

  $ export NEXTSTRAIN_AWS_BATCH_WORKDIR_URL="s3://nextstrain-tmp/$(python3 -c 'import uuid; print(uuid.uuid4())').zip"

  $ aws s3 cp --quiet "$TESTDIR/data/workdir-without-overlays.zip" "$NEXTSTRAIN_AWS_BATCH_WORKDIR_URL"

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} --env=AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch bash -euo pipefail -xc 'ls -l'
  download: s3://nextstrain-tmp/*.zip to ../build.zip (glob)
  Archive:  /nextstrain/build.zip
   extracting: reticulating            
   extracting: splines                 
  + ls -l
  total 0
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 reticulating
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 splines
  upload: ../build.zip to s3://nextstrain-tmp/*.zip (glob)

/nextstrain/{augur,auspice} are removed when the workdir ZIP contains overlays.

  $ export NEXTSTRAIN_AWS_BATCH_WORKDIR_URL="s3://nextstrain-tmp/$(python3 -c 'import uuid; print(uuid.uuid4())').zip"

  $ aws s3 cp --quiet "$TESTDIR/data/workdir-with-augur-auspice-overlays.zip" "$NEXTSTRAIN_AWS_BATCH_WORKDIR_URL"

  $ docker run --rm --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} --env=AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch bash -euo pipefail -xc 'ls -lR . ../augur ../auspice'
  download: s3://nextstrain-tmp/*.zip to ../build.zip (glob)
  removing /nextstrain/augur because workdir ZIP contains ../augur/ overlay
  removing /nextstrain/auspice because workdir ZIP contains ../auspice/ overlay
  Archive:  /nextstrain/build.zip
   extracting: reticulating            
   extracting: splines                 
     creating: ../augur/
     creating: ../augur/a/
     creating: ../augur/a/b/
     creating: ../augur/a/b/c/
   extracting: ../augur/a/b/c/world.txt  
   extracting: ../augur/a/b/c/hello.txt  
     creating: ../augur/augur/
   extracting: ../augur/augur/__init__.py  
   extracting: ../augur/README.md      
     creating: ../auspice/
  + ls -lR . ../augur ../auspice
  .:
  total 0
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 reticulating
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 splines
  
  ../augur:
  total 12
  -rw-rw-r-- 1 nextstrain nextstrain   22 Mar 10 21:45 README.md
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 a
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:46 augur
  
  ../augur/a:
  total 4
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 b
  
  ../augur/a/b:
  total 4
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:33 c
  
  ../augur/a/b/c:
  total 8
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 hello.txt
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 world.txt
  
  ../augur/augur:
  total 4
  -rw-rw-r-- 1 nextstrain nextstrain 34 Mar 10 21:46 __init__.py
  
  ../auspice:
  total 0
  upload: ../build.zip to s3://nextstrain-tmp/*.zip (glob)

…even when the workdir is not /nextstrain/build, e.g. when it's a sibling.

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/abc --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} --env=AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch bash -euo pipefail -xc 'ls -lR . ../augur ../auspice'
  download: s3://nextstrain-tmp/*.zip to ../abc.zip (glob)
  removing /nextstrain/augur because workdir ZIP contains ../augur/ overlay
  removing /nextstrain/auspice because workdir ZIP contains ../auspice/ overlay
  Archive:  /nextstrain/abc.zip
   extracting: reticulating            
   extracting: splines                 
     creating: ../augur/
     creating: ../augur/a/
     creating: ../augur/a/b/
     creating: ../augur/a/b/c/
   extracting: ../augur/a/b/c/world.txt  
   extracting: ../augur/a/b/c/hello.txt  
     creating: ../augur/augur/
   extracting: ../augur/augur/__init__.py  
   extracting: ../augur/README.md      
     creating: ../auspice/
  + ls -lR . ../augur ../auspice
  .:
  total 0
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 reticulating
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 splines
  
  ../augur:
  total 12
  -rw-rw-r-- 1 nextstrain nextstrain   22 Mar 10 21:45 README.md
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 a
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:46 augur
  
  ../augur/a:
  total 4
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 b
  
  ../augur/a/b:
  total 4
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:33 c
  
  ../augur/a/b/c:
  total 8
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 hello.txt
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 world.txt
  
  ../augur/augur:
  total 4
  -rw-rw-r-- 1 nextstrain nextstrain 34 Mar 10 21:46 __init__.py
  
  ../auspice:
  total 0
  upload: ../abc.zip to s3://nextstrain-tmp/*.zip (glob)

…but not when the workdir is somewhere completely different.

  $ docker run --rm --env=NEXTSTRAIN_WORKDIR=/nextstrain/x/y/z --env=NEXTSTRAIN_AWS_BATCH_{WORKDIR_URL,VERBOSE} --env=AWS_{ACCESS_KEY_ID,SECRET_ACCESS_KEY,SESSION_TOKEN} "$IMAGE" \
  >   /sbin/entrypoint-aws-batch bash -euo pipefail -xc 'ls -lR . ../augur ../auspice; realpath ../augur ../auspice'
  download: s3://nextstrain-tmp/*.zip to ../z.zip (glob)
  Archive:  /nextstrain/x/y/z.zip
   extracting: reticulating            
   extracting: splines                 
     creating: ../augur/
     creating: ../augur/a/
     creating: ../augur/a/b/
     creating: ../augur/a/b/c/
   extracting: ../augur/a/b/c/world.txt  
   extracting: ../augur/a/b/c/hello.txt  
     creating: ../augur/augur/
   extracting: ../augur/augur/__init__.py  
   extracting: ../augur/README.md      
     creating: ../auspice/
  + ls -lR . ../augur ../auspice
  .:
  total 0
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 reticulating
  -rw-rw-r-- 1 nextstrain nextstrain 0 Mar 10 21:46 splines
  
  ../augur:
  total 12
  -rw-rw-r-- 1 nextstrain nextstrain   22 Mar 10 21:45 README.md
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 a
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:46 augur
  
  ../augur/a:
  total 4
  drwxrwxr-x 3 nextstrain nextstrain 4096 Mar 10 21:32 b
  
  ../augur/a/b:
  total 4
  drwxrwxr-x 2 nextstrain nextstrain 4096 Mar 10 21:33 c
  
  ../augur/a/b/c:
  total 8
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 hello.txt
  -rw-rw-r-- 1 nextstrain nextstrain 6 Mar 10 21:32 world.txt
  
  ../augur/augur:
  total 4
  -rw-rw-r-- 1 nextstrain nextstrain 34 Mar 10 21:46 __init__.py
  
  ../auspice:
  total 0
  + realpath ../augur ../auspice
  /nextstrain/x/y/augur
  /nextstrain/x/y/auspice
  upload: ../z.zip to s3://nextstrain-tmp/*.zip (glob)
