---
name: update-search-fork-from-upstream
description: Use when updating, syncing, or pulling the Search browser fork (chanatundev/Search) up to date with upstream Search (driceroland/Search), resolving merge conflicts between the fork and upstream, or when the fork is missing upstream Search fixes, features, or versions, including when the installed fork shows a "Search X is out" update prompt.
---

# Update the Search fork from upstream

`chanatundev/Search` is a fork of `driceroland/Search`, a SwiftPM/WebKit macOS
browser. The fork's history contains upstream. Update it by **merging the tip of
`upstream/main`**. Previous syncs went past the latest release tag, so follow
`main`, not tags. Never rebase fork commits and never force-push `origin`.

The installed fork is ad-hoc signed, so its updater can't install upstream
releases by itself. Instead, a "Search X is out" prompt appears, and that prompt is
the cue to run this sync. Never choose "Download Update": it installs Office
Commun's build over the fork.

## 1. Preflight

```bash
git status --short                      # must be clean
git remote get-url upstream 2>/dev/null \
  || git remote add upstream https://github.com/driceroland/Search.git
git fetch upstream && git fetch origin
git switch main && git merge --ff-only origin/main
git branch --list 'merge/upstream-*' --no-merged main   # earlier syncs that never landed
MB=$(git merge-base HEAD upstream/main)
git rev-list --count HEAD..upstream/main   # 0 → already up to date, stop
git log --oneline --no-merges upstream/main..HEAD   # fork-only commits to protect
```

If `--no-merged` lists a branch, an earlier sync never reached `main`. Ask whether
to land it first, build on top of it, or leave it alone. Never delete it without asking.

## 2. Preview conflicts without touching the tree

```bash
git merge-tree --write-tree --name-only HEAD upstream/main
git log --oneline --no-merges HEAD..upstream/main    # scan for overlap with fork features
```

The lines after the tree hash are conflicted files. For each one, read
`git log --oneline $MB..HEAD -- <file>` and `git log --oneline $MB..upstream/main -- <file>`.
Collect open questions from this step, check them against [When to ask](#when-to-ask),
and ask them all in one batch before you start the merge.

## 3. Merge on a sync branch

```bash
UP=$(git rev-parse --short upstream/main)
V=$(git show upstream/main:VERSION)
B=merge/upstream-$V; git rev-parse -q --verify $B >/dev/null && B=$B-$UP
git switch -c $B
git merge --no-ff --no-commit upstream/main
```

Resolve every conflict with the rules below. Commit when
`git diff --name-only --diff-filter=U` is empty and no `<<<<<<<` markers remain.

## Resolution rules

The default is to keep **both** sides: take upstream's change and re-apply the
fork's intent on top of it. Take one side wholesale only when a row below says so.

| Area | Rule |
|---|---|
| Command palette: `CommandPalette.swift`, the "Command Palette…" `⌘E` menu item in `App.swift`, the palette sheet and `browser.commandPalette` guards | Keep. When upstream adds a new browser action, menu command, or panel, add it to the palette's action list too. |
| Sleep actions: `Sleep.swift` and its palette entries | Keep. Port to upstream's tab and Space model if upstream changed it. |
| Multi-tab selection in `Browser.swift`, `TabBar.swift`, `Side.swift` and `App.swift`: `⌘`-click and `⌘⇧`-click selection, copy URLs, `⇧⌘V` multi-paste, close selected, move to Space | Keep. Union tab context menus with upstream's new items. New tab layouts from upstream, such as pinned rows, groups, or Split View panes, must still support selection. |
| Space switching (`1`–`9`) in the palette | Keep, and follow upstream's Space API. |
| `README.md` | Keep the fork section above `# Upstream Search`. Replace everything below that heading with upstream's `README.md` minus its `# Search` title line, then put back fork rows in it, such as the `⌘E` row in the shortcuts table. |
| `build.sh` | Take upstream's version, then keep the fork's `xattr -cr "$APP"` line before codesigning. |
| `CHANGELOG.md`, `ROADMAP.md`, `VERSION`, `CONTRIBUTING.md`, `SECURITY.md`, `publish.sh`, `Updater.swift`, `skill/`, `Tests/` | Take upstream's version. These files have no fork edits. If `git log $MB..HEAD -- <file>` shows otherwise, treat that file like a fork feature. |

## When to ask

If a question matches a row in the table above, follow the table. Ask the user
only when one of these is true:

| Trigger | Example question |
|---|---|
| Upstream took a fork shortcut (`⌘E`, `⇧⌘V`, `⌘`-click, `⌘⇧`-click) for something else | "Upstream bound `⌘E` to Use Selection for Find. Move the palette to another key, or keep `⌘E` for it?" |
| Upstream shipped a feature that overlaps a fork feature | "Upstream added its own tab sleeping. Keep `Sleep.swift`, switch the palette to upstream's, or keep both?" |
| Upstream deleted or redesigned code a fork feature depends on, and keeping it means re-implementing it, not porting it | "Upstream rewrote the tab bar as a new view. Rebuild multi-select on it, or ship this sync without it?" |
| Both sides changed the same behavior in incompatible ways | "Both sides changed what a `⌘`-click on a tab does. Which wins?" |
| Fixing a build error would change how a fork feature behaves, beyond a rename or signature update | "Spaces now have their own data stores per profile. Should move-to-Space recreate tabs across profiles too?" |

How to ask:

- Batch questions at a checkpoint, either after the step 2 preview or after the
  first pass of resolution. Don't stop once per file.
- Use AskUserQuestion. Offer 2-4 concrete options, put your recommendation first,
  and name the file plus the fork and upstream commit subjects involved.
- While waiting, keep resolving files the questions don't affect. Don't commit
  the merge until every question is answered.
- Record each answer in the merge commit message.

## 4. Verify

The repo lives in iCloud Drive, which adds extended attributes to everything
under `.build`. Code signing rejects those files ("resource fork, Finder information,
or similar detritus not allowed"), so build in a scratch folder outside iCloud:

```bash
S="${TMPDIR:-/tmp}/search-fork-build"
swift build --scratch-path "$S" 2>&1 | grep -E 'warning:|error:'   # no errors, and no new warnings in files you resolved
swift test --scratch-path "$S"
```

`DownloadLifecycleTests` time out now and then against their local server, even
on unchanged upstream code. Before blaming the merge for a timeout, rerun it with
`--filter <TestCase>`. Treat a failure as caused by the merge only if it keeps
failing and passes on `main`.

If the build fails in a file you didn't touch, it's usually a fork feature
calling an API upstream renamed. Fix the fork code, not upstream's. Offer to run
`./build.sh` so the user can try `⌘E`, multi-select, and move-to-Space in a real
`.app`. Don't click through the UI yourself unless the user asks you to.

## 5. Commit and land

```bash
git commit    # message below
git switch main && git merge --ff-only $B
```

Commit message, matching earlier syncs:

```
Merge upstream main v<V> (<UP>) into fork

Brings in <N> upstream commits (<MB short>..<UP>).
Conflicts: <file> — <what was kept from each side>; ...
Decisions: <question — user's answer>; ... (omit if none were asked)
```

Ask before running `git push origin main`, because it publishes the fork. Keep
the sync branch until the push is done.

## Common mistakes

- **Syncing to the latest tag.** This fork tracks `upstream/main`, so a tag would move the fork backwards.
- **Rebasing onto upstream.** This rewrites published fork commits. Merge instead.
- **Resolving a file wholesale with `--theirs` or `--ours`.** This silently drops the other side's feature. Use it only where the table allows it.
- **Leaving the palette out of date.** A new upstream action that's missing from `⌘E` is a quiet regression.
- **Updating the README's fork section to describe upstream changes.** It describes fork additions only.
- **Guessing on a trigger from "When to ask".** Ask instead. Asking about something the table already settles is also a mistake: apply the rule.
