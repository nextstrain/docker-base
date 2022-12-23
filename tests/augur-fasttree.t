Use augur tree with FastTree

  $ cat >test.fasta <<~~
  > > SEQ1
  > ACTG
  > > SEQ2
  > ACCG
  > > SEQ3
  > ACAG
  > > SEQ4
  > ACGG
  > ~~

  $ augur tree --alignment test.fasta --method fasttree > /dev/null
