#!/bin/sh

## inputs

FILE="sub-amu01/dwi/sub-amu01_dwi.nii.gz" # example file to download and cache

## utils

unset USED LASTUSED
inspect() {
  # find and print all hardlinks to the example file
  # and total disk usage across all dataset copies
  
  # hardlinks
  echo
  (
  if test -f data-multi-subject1/"$FILE"; then
    inode=$(stat -c "%i" data-multi-subject1/"$FILE"); 
    (inode2_clause=$(
        if test -f data-multi-subject2/"$FILE"; then
          inode2=$(stat -c "%i" data-multi-subject2/"$FILE")
          if [ "$inode" != "$inode2" ]; then
            echo '-o -inum '"$inode2"
          fi
        fi
     )
     set -x;
     find . \( -inum "$inode" $inode2_clause \) -exec stat -c "%A %h %U %s %n" {} \;
    ) 2>&1 |
    ( # force the inode numbers to appear all the same, for the same of reproducibility and easier diffing
      # their actual values are irrelevant
      sed -E 's/-inum [[:digit:]]+/-inum 00000/g' # just k
    )
  fi
  
  # disk usage
  USED=$(du -s -b . | awk '{print $1}')
  echo
  echo -n "Disk usage: $USED"
  if [ -n "$LASTUSED" ]; then
    echo -n " (change: $(("$USED" - "$LASTUSED")))"
  fi
  echo " bytes"
  
  ) |
  sed 's/^/    inspect: /'
  echo

  LASTUSED=$USED
}


## main

echo ">>>>>>>> Platform <<<<<<<<"
uname -a
cat /etc/os-release
git annex version
echo


echo ">>>>>>>> Config <<<<<<<<"
cd $(mktemp -d) # start fresh

inspect

echo ">>>>>>>> Init cache <<<<<<<<"
git init --bare .annex-cache
(cd .annex-cache;
  git annex init;
  git config annex.hardlink true;
  git annex untrust here

  # quiet git
  git config advice.detachedHead false
  git config annex.alwayscommit false
)

inspect

# make a first copy to test + populate the cache from
echo ">>>>>>>> Make a first copy <<<<<<<<"
echo "         This copy will download from external data storage and upload to the cache"
git clone -b r20201130 https://github.com/spine-generic/data-multi-subject data-multi-subject1
(cd data-multi-subject1
  git config remote.origin.annex-ignore true
  git remote add cache ../.annex-cache
  git config remote.cache.annex-speculate-present true
  git config remote.cache.annex-cost 10
  git config remote.cache.annex-pull false
  git config remote.cache.annex-push false
  git config remote.cache.fetch do-not-fetch-from-this-remote:

  # checksumming is a large fraction of time
  # save this time by trusting Github to keep data integrity.
  git config remote.cache.annex-verify false

  # quiet git
  git config advice.detachedHead false
  git config annex.alwayscommit false
  
  git annex init # write the basic .git/annex/ files, so their sizes aren't distracting in inspect()
)

inspect

echo ">>>>>>>> Download from external data hosting (amazon) <<<<<<<<"
(cd data-multi-subject1; git config annex.thin true; git config annex.hardlink false);
(cd data-multi-subject1; git annex get "$FILE")

inspect

echo ">>>>>>>> Populating cache <<<<<<<<"
(cd data-multi-subject1; git annex copy --to cache)

inspect

echo ">>>>>>>> Make a second copy <<<<<<<<"
git clone -b r20201130 https://github.com/spine-generic/data-multi-subject data-multi-subject2
(cd data-multi-subject2
  git config remote.origin.annex-ignore true
  git remote add cache ../.annex-cache
  git config remote.cache.annex-speculate-present true
  git config remote.cache.annex-cost 10
  git config remote.cache.annex-pull false
  git config remote.cache.annex-push false
  git config remote.cache.fetch do-not-fetch-from-this-remote:

  # checksumming is a large fraction of time
  # save this time by trusting Github to keep data integrity.
  git config remote.cache.annex-verify false

  # quiet git
  git config advice.detachedHead false
  git config annex.alwayscommit false
  
  git annex init
)


inspect

echo ">>>>>>>> Download from internal data hosting cache <<<<<<<<"
(cd data-multi-subject2; git config annex.thin true; git config annex.hardlink false);
(cd data-multi-subject2; git annex get "$FILE")

inspect


pwd # DEBUG