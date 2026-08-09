# Host↔guest content-addressed sync (CAS)

Primary workspace wire format between the Compass host and the embedded macOS
VM guest (`SharedCompassVMCASSync`).

Git remains the **host project VCS** (and the generated app’s GitHub surface).
It is not required as the host↔guest transport.

## Status

**Implemented** as the agent bash primary path. Wipe-style tar is used for
agent `forceRefresh` and `vm reset-workspace --full` resync, and as a logged
fallback when incremental CAS fails.

## Motivation

| Transport | Strengths | Weaknesses |
|---|---|---|
| CAS (current primary) | Deltas; in-place apply preserves `target/` / `.build/`; no guest git/SSH | Newer; blob size still bound by vsock frame budget |
| Tar over vsock | Works without guest git | Full-tree wipe every push; destroys build caches |

## Goals

- Gitignore-aware dirty host snapshots (tracked + untracked-not-ignored)
- Hard exclude of build dirs (`pullSideExcludeDirs`)
- **In-place** guest apply so `target/`, `.build/`, etc. survive syncs
- True deltas: transfer only missing content
- Symmetric guest→host pull for `pullAfterRun` without ephemeral git merges
- Catalog fingerprint + fileset coherence
- Fail loud on oversized blobs (`maxBlobByteCount`)
- No SSH dependency for workspace sync

## Model

```
Host syncable tree
       │
       ▼
Tree manifest (path → hash)
       │
       ├── missing blob hashes ──► vsock writeFile ──► Guest object store
       │                              Repos/<id>/objects/
       ▼
In-place materialize worktree (add / update / delete syncable paths only)
```

### Object store layout

```
/Users/compass/Compass/Repos/<uuid>/
  worktree/          # materialised tree (agent bash cwd)
  objects/ab/cd…     # CAS blobs by hash prefix
  manifest.json      # last applied tree
```

## Push / pull

See `SharedCompassVMCASSync.syncToGuest` / `pullFromGuest`. The bash runner
(`AgentMacOSVMBashRunner`) uses `.cas` as `SyncTransport` and pairs pull to
the same transport; tar fallback logs under the `WorkspaceSync` OSLog category.

## Non-goals

- Replacing git as project / GitHub VCS
- Bringing back VirtioFS (removed; CAS/tar sync is the path)
- AI-native semantic version control
