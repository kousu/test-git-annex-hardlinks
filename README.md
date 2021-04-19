# hardlink git-annex bug

I am attempting to [cache `git-annex`](https://git-annex.branchable.com/tips/local_caching_of_annexed_files/),
in order to hopefully save time and bandwidth when running a [linter](https://github.com/bids-standard/bids-validator)
over a large dataset. It is pretty expensive to download 10GB for a one line change, but that is where we're at right now.

Moreover, once I implement caching, I want to make sure it uses **hardlinks**, because

1. the extra copies take extra time
    - on a professional-grade data center, it is almost as slow to make copies as to download in the first place.
3. using extra space risks overrunning the disk; so doubling or maybe accidentally tripling the space is not an option.

Naively, my 10GB dataset ballooned to 20GB when I added the caching system [recommended by the `git-annex` wiki](https://git-annex.branchable.com/tips/local_caching_of_annexed_files/):

The process that initially populates the cache only uses 10GB, because `annex.thin` is enabled in the repo
so it hardlinks the content to the `.git/annex/objects/` files, and `annex.hardlink` is enabled on the cache,
so the populate step hardlinks the cache's `.git/annex/objects/` files back to the repo's `.git/annex/objects`, too.

You can see this by running `./annex-hardlink.sh`, or reading the [log](./log.txt). First:

```
[...]
(cd data-multi-subject1; git config annex.thin true; git config annex.hardlink false);
[...]

echo ">>>>>>>> Populating cache <<<<<<<<"
(cd data-multi-subject1; git annex copy --to cache)

inspect
```

produces:


> ```
> >>>>>>>> Populating cache <<<<<<<<
> copy sub-amu01/dwi/sub-amu01_dwi.nii.gz (to cache...) 
> ok
>
>    inspect: + find . '(' -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
>    inspect: -r--r--r-- 3 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
>    inspect: -r--r--r-- 3 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
>    inspect: -r--r--r-- 3 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
>    inspect: 
>    inspect: Disk usage: 20554625 (change: 2203) bytes
> ```


See, the content has 3 hardlinks, and uploading to the cache has only increased disk usage by 2KiB, barely anything.
It is probably just a bit of extra metadata stored by git-annex, the filesystem, etc.

> ⚠️ By the way, this behaviour is contrary to what's in [git-annex(1)](https://manpages.debian.org/unstable/git-annex/git-annex.1.en.html#CONFIGURATION)
> 
> >               When annex.thin is also set, setting annex.hardlink has no effect.
> 
> Instead, `git annex copy` looked at the cache repo, saw `annex.hardlink true` there,
> and decided to ignore `annex.thin` and `annex.hardlink` in the local repo;
> however this is exactly the behaviour I *want* so I left it alone.

Next, I tried to get it back. The script makes `data-multi-subject2` the same as the first,
and tries to download content:

```
echo ">>>>>>>> Download from internal data hosting cache <<<<<<<<"
(cd data-multi-subject2; git config annex.thin true; git config annex.hardlink false);
(cd data-multi-subject2; git annex get "$FILE")
```

This produces

```
>>>>>>>> Download from internal data hosting cache <<<<<<<<
get sub-amu01/dwi/sub-amu01_dwi.nii.gz (from cache...) 
ok
(recording state in git...)

    inspect: + find . '(' -inum 00000 -o -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
    inspect: -rw-r--r-- 1 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
    inspect: -r--r--r-- 4 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
    inspect: 
    inspect: Disk usage: 41081259 (change: 8902446) bytes
```

Here it got the content from the cache, and, again contrary to what the docs claim,
*ignored* `annex.thin` to use `annex.hardlink` instead: there are now 4 hardlinks to the same file.
But, additionally, it *checked out* the file, making a completely new copy in `data-multi-subject2`'s
working dir -- the one with only 1 hardlink.

So what can I do? Is there a way I can get this down to only 10GB?

## `no-cache-hardlink`

I also tried disabling `annex.hardlink` entirely, by disabling it on the cache repo, with this patch 

```diff
$ git diff annex-cache..no-cache-hardlinks -- ./annex-hardlinks.sh 
diff --git a/annex-hardlinks.sh b/annex-hardlinks.sh
index 49a7e19..b720202 100755
--- a/annex-hardlinks.sh
+++ b/annex-hardlinks.sh
@@ -162,6 +162,7 @@ git clone -b r20201130 https://github.com/spine-generic/data-multi-subject data-
 inspect
 
 echo ">>>>>>>> Download from internal data hosting cache <<<<<<<<"
+(cd .annex-cache; git config annex.hardlink false)
 (cd data-multi-subject2; git config annex.thin true; git config annex.hardlink false);
 (cd data-multi-subject2; git annex get "$FILE")
```

Which made the output change like this:

```diff
]$ git diff annex-cache..no-cache-hardlinks -- log.txt
diff --git a/log.txt b/log.txt
index c08a900..ce9c894 100644
--- a/log.txt
+++ b/log.txt
[...]
>>>>>>>>> Download from internal data hosting cache <<<<<<<<
 get sub-amu01/dwi/sub-amu01_dwi.nii.gz (from cache...) 
-^Mok
+^M0%    31.98 KiB        19 MiB/s 0s^M100%  8.49 MiB          1 GiB/s 0s^M                                  ^Mok
 (recording state in git...)
 
     inspect: + find . '(' -inum 00000 -o -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
-    inspect: -rw-r--r-- 1 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
-    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
-    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
-    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
-    inspect: -r--r--r-- 4 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -rw-r--r-- 2 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -rw-r--r-- 2 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 3 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 3 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 3 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
     inspect: 
-    inspect: Disk usage: 41081257 (change: 8902446) bytes
+    inspect: Disk usage: 41081259 (change: 8902447) bytes
[...]
```

In this case, `data-multi-subject2`'s `.git/annex/objects` made a fresh, un-hardlinked, copy,
and then `annex.thin` hardlinked the content into that.
Effectively the same result, and with the same storage requirements at the end: "41081259 bytes".


## `annex-fix`

I tried using `git annex fix` which [promises](https://manpages.debian.org/unstable/git-annex/git-annex-fix.1.en.html#DESCRIPTION)

> Also, adjusts unlocked files to be copies or hard links as configured by annex.thin.

```diff
$ git diff annex-cache..annex-fix
[...]
diff --git a/annex-hardlinks.sh b/annex-hardlinks.sh
index 49a7e19..f390fb6 100755
--- a/annex-hardlinks.sh
+++ b/annex-hardlinks.sh
@@ -167,5 +167,10 @@ echo ">>>>>>>> Download from internal data hosting cache <<<<<<<<"
 
 inspect
 
+echo ">>>>>>>> attempt git-annex fix <<<<<<<<"
+(cd data-multi-subject2; git-annex fix "$FILE")
+
+inspect
+
```

But it had no effect, I still came out with 1 and 4 hardlinks to two copies respectively:

```diff
$ git diff annex-cache..annex-fix
[...]
diff --git a/log.txt b/log.txt
index c08a900..2960a80 100644
--- a/log.txt
+++ b/log.txt
[...]
+>>>>>>>> attempt git-annex fix <<<<<<<<
+
+    inspect: + find . '(' -inum 00000 -o -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
+    inspect: -rw-r--r-- 1 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 4 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: 
+    inspect: Disk usage: 41081254 (change: 1) bytes
[...]
```


I don't really want to _fix_ the files anyway, I want the wasted copies to never be made in the first place.

## 🎺 `bare` 🎺

I tried treating `data-multi-subject2/.git` as a bare repo and then trying to treat it as a non-bare repo.

```
$ git diff annex-cache..bare -- ./annex-hardlinks.sh 
diff --git a/annex-hardlinks.sh b/annex-hardlinks.sh
index 49a7e19..8eb7768 100755
--- a/annex-hardlinks.sh
+++ b/annex-hardlinks.sh
[...]
@@ -163,7 +163,37 @@ inspect
 
 echo ">>>>>>>> Download from internal data hosting cache <<<<<<<<"
 (cd data-multi-subject2; git config annex.thin true; git config annex.hardlink false);
-(cd data-multi-subject2; git annex get "$FILE")
+
+# temporarily pretend to be a bare repo, to disable the checkout routine
+(cd data-multi-subject2/.git/; git config core.bare true; git remote set-url cache ../../.annex-cache)
+(cd data-multi-subject2/.git; git annex copy --from cache) # hardlink anything that exists in .annex-cache into our .git/annex/objects
+(cd data-multi-subject2/; git config core.bare false; git remote set-url cache ../.annex-cache)
+
+inspect
+
```

This trick successfully **disables** the checkout logic; notice how after this step the lone 1-link copy is still 105 bytes,
meaning it's just the annex pointer.

```diff
$ git diff annex-cache..bare -- log.txt
diff --git a/log.txt b/log.txt
index c08a900..49ce6dc 100644
--- a/log.txt
+++ b/log.txt
[...]
     inspect: + find . '(' -inum 00000 -o -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
-    inspect: -rw-r--r-- 1 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
-    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -rw-r--r-- 1 kousu 105 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject2/.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
     inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
     inspect: -r--r--r-- 4 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
     inspect: -r--r--r-- 4 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
     inspect: 
-    inspect: Disk usage: 41081257 (change: 8902446) bytes
+    inspect: Disk usage: 32288850 (change: 110031) bytes
+
+>>>>>>>> Emulate annex.thin checkout from local .git/annex/objects <<<<<<<<
+'sub-amu01/dwi/sub-amu01_dwi.nii.gz' => '.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz'
+
+    inspect: + find . '(' -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject2/.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: 
+    inspect: Disk usage: 32288745 (change: -105) bytes
```

But no matter what I tried, `git annex copy`, `git annex get`, different `git config` settings, `git annex fix`,
I couldn't get from that state to a checked out hardlink.
Sometimes `git annex get` would just return immediately without saying or doing anything;
othertimes it or `git annex copy` would download from amazon. I haven't disentangled this part.
It seems there is some location tracking data missing when `copy` works on a bare repo.

Eventually I gave up and wrote my own `git annex get` that understands this situation:

```diff
$ git diff annex-cache..bare -- ./annex-hardlinks.sh 
[...]
+echo ">>>>>>>> Emulate annex.thin checkout from local .git/annex/objects <<<<<<<<"
+# side-step git-annex entirely, and just make hardlinks ourselves
+# since git-annex copy and git-annex get both insist on doing download+checkout in one step,
+# and git-annex smudge and git-annex fix seem to give up immediately,
+# construct all the hardlinks they *would* construct ourselves.
+
+# for each available annex file
+# find all the annex pointers *to* it
+# annex pointers look like: ''
+# $ cat sub-amu02/dwi/sub-amu02_dwi.nii.gz
+# /annex/objects/SHA256E-s8988723--f0a6e2cb764e14aa239191f7717a2bdb6c54ce51301e794faba48b9aea11cfc9.nii.gz
+# While actual annex files look like:
+# .git/annex/objects/<something>/<something>/SHA256E-s8988723--f0a6e2cb764e14aa239191f7717a2bdb6c54ce51301e794faba48b9aea11cfc9.nii.gz/SHA256E-s8988723--f0a6e2cb764e14aa239191f7717a2bdb6c54ce51301e794faba48b9aea11cfc9.nii.gz
+# so this matches the two up
+(cd data-multi-subject2;
+  find .git/annex/objects/ -type f |
+  while read object; do
+    git grep -l "$(basename "$object")" |
+    while read checkout; do
+      ln -vf "$object" "$checkout"
+    done
+  done
+)
```

And this **finally succeeded in using only one copy**.

```diff
$ git diff annex-cache..bare -- log.txt
[...]
+>>>>>>>> Emulate annex.thin checkout from local .git/annex/objects <<<<<<<<
+'sub-amu01/dwi/sub-amu01_dwi.nii.gz' => '.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz'
+
+    inspect: + find . '(' -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject2/.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject1/sub-amu01/dwi/sub-amu01_dwi.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./data-multi-subject1/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: -r--r--r-- 5 kousu 8901683 ./.annex-cache/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
+    inspect: 
+    inspect: Disk usage: 32288745 (change: -105) bytes
```


The only problem is, doing a regular `get` then makes an extra, unnecessary, hardlink in the same annex:

```
>>>>>>>> Fixup <<<<<<<<
get sub-amu01/dwi/sub-amu01_dwi.nii.gz (from cache...) 
ok

    inspect: + find . '(' -inum 00000 ')' -exec stat -c '%A %h %U %s %n' '{}' ';'
    inspect: -r--r--r-- 6 kousu 8901683 ./data-multi-subject2/sub-amu01/dwi/sub-amu01_dwi.nii.gz
    inspect: -r--r--r-- 6 kousu 8901683 ./data-multi-subject2/.git/annex/objects/18/9Q/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
    inspect: -r--r--r-- 6 kousu 8901683 ./data-multi-subject2/.git/annex/objects/686/8a7/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz/SHA256E-s8901683--cc39b2f0bea6673904d3926dc899f339ac59f5f9a114563fe01b20278b99435d.nii.gz
[...]
```

## `envelop-cache`

In the context of CI, it seems silly to make two separate folders for one set of files, so I tried to `mv .annex-cache/annex data-multi-subject2/.git/`.
Benefitting from the previous successful workaround, it appeared to work, except that `get` is broken: it appears to work but doesn't actually check the files out:

```
get sub-amu02/anat/sub-amu02_T1w.nii.gz (from amazon...) 

(checksum...) ok                      
get sub-amu02/anat/sub-amu02_T2star.nii.gz (from amazon...) 

(checksum...) ok                   
get sub-amu02/anat/sub-amu02_T2w.nii.gz (from amazon...) 

(checksum...) ok                     
get sub-amu02/anat/sub-amu02_acq-MToff_MTS.nii.gz (from amazon...) 

(checksum...) ok                   
get sub-amu02/anat/sub-amu02_acq-MTon_MTS.nii.gz (from amazon...) 

(checksum...) ok                   
get sub-amu02/anat/sub-amu02_acq-T1w_MTS.nii.gz (from amazon...) 

(checksum...) ok                  
get sub-amu02/dwi/sub-amu02_acq-b0_dwi.nii.gz (from amazon...) 

(checksum...) ok                  
get sub-amu02/dwi/sub-amu02_dwi.nii.gz (from amazon...) 

(checksum...) ok                     
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/anat/sub-amu02_acq-MToff_MTS.nii.gz
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/anat/sub-amu02_acq-MTon_MTS.nii.gz
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/anat/sub-amu02_acq-T1w_MTS.nii.gz
-rw-r--r-- 1 kousu kousu 106 Apr 16 02:52 sub-amu02/anat/sub-amu02_T1w.nii.gz
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/anat/sub-amu02_T2star.nii.gz
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/anat/sub-amu02_T2w.nii.gz
-rw-r--r-- 1 kousu kousu 104 Apr 16 02:52 sub-amu02/dwi/sub-amu02_acq-b0_dwi.nii.gz
-rw-r--r-- 1 kousu kousu 105 Apr 16 02:52 sub-amu02/dwi/sub-amu02_dwi.nii.gz
```

## Conclusion

So eventually I got it working, but only by sidestepping git-annex.

Is there a better way?

### Details

I made the log files with `./mklogs.sh`. But sometimes I had try a few times before it would work because of https://github.com/neuropoly/data-management/issues/72, so some branches I just did manually:

```
$ git checkout branch && ./annex-hardlinks.sh | tee log.txt && git add log.txt && git commit -m "Log"
```

