---
name: notes
description: The user's ideas and todos, kept as markdown files in a git repo and managed with the `note` command. Use when the user wants to note, capture or remember an idea, add a todo, asks what's on their list or what they meant to do, or when work you just finished may be on it.
---

# Notes: ideas and todos

The user keeps ideas and todos in a git repo of markdown files, one file per item:
`ideas/<date>-<slug>.md` and `todos/<date>-<slug>.md`. `note dir` prints where the repo is.

Use the `note` command for everything it covers. It pulls first, commits only the files it
touched, and pushes, all under a lock, so several agents can use it at once. **Don't run git in
the notes repo yourself**; after editing a file by hand, run `note sync "<what changed>"`.

## Adding

```sh
note add -t todo "Short title" -m "A paragraph of context" -m "Another one" --tag a,b
idea "Short title" -m "…"      # same as note add -t idea
todo "Short title" -m "…"      # same as note add -t todo
```

- **idea** is something worth thinking about later; **todo** is a concrete thing to do. If
  the user doesn't say, pick from what they said ("remind me to…" is a todo).
- Keep titles short. A todo's title starts with a verb.
- The body holds what the user said, plus context you have that they'd want later: the files,
  links, error messages or decisions it came from. Don't invent requirements.
- `project` is filled in from the repo you're working in (`host/owner/repo`). Pass `-P` when
  the item has nothing to do with that repo, or `-p host/owner/repo` for a different one.
- It prints the new file's path. For a long body, add the item, edit that file, then
  `note sync "flesh out <title>"`.
- Tell the user the file you created.

## Finding

```sh
note ls              # open and in-progress items
note ls -a           # everything, including done and dropped
note ls -t todo --tag agents
note ls -H           # only items for the repo you're in
note show <ref>      # <ref>: the file name, or any unique part of it
```

`note ls` prints `status type name title [tags] (project)`. To search the text, `rg` in
`$(note dir)`.

## Changing

```sh
note start <ref>     # status: doing
note done <ref>      # status: done
note drop <ref>      # status: dropped
note reopen <ref>    # status: open
note promote <ref>   # an idea becomes a todo (moves it to todos/)
```

For anything else, edit the file (`note path <ref>`) and run `note sync "<what changed>"`.
Before changing frontmatter by hand, read the repo's `AGENTS.md` (`$(note dir)/AGENTS.md`);
it describes the format.

When you finish work that an open todo describes, say so, and mark it done if the user agrees
or asked for exactly that work.

If `note` warns that it couldn't push or rebase, the change is saved locally; tell the user
rather than fixing git in the notes repo yourself.
