#!/bin/sh

git for-each-ref --format="%(refname:short)" | while read branch; do
  git checkout "$branch" &&
  (./annex-hardlinks.sh | tee log.txt) &&
  git add log.txt &&
  git commit -m "Save output for $(git describe --always)";
done

# to view results:
#git for-each-ref --format="%(refname:short)" | while read branch; do git show "$branch":log.txt; done
#or
# git diff branch1 branch2
