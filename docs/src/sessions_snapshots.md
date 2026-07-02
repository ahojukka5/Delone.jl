# Live sessions and snapshots

Delone.jl exposes a geometry-backed mesh hierarchy in two complementary
forms:

- a **live session** ([`MeshHierarchySession`](@ref)) — the authoritative,
  mutable state a solver keeps *during* a simulation;
- **copied snapshots** ([`MeshLevelSnapshot`](@ref),
  [`HierarchyTransferSnapshot`](@ref), [`MeshHierarchySnapshot`](@ref)) —
  consumer-agnostic, plain-array data derived from the session.

The two are kept deliberately distinct: the live Netgen mesh handles are
authoritative and can be mutated as the solve/adapt loop proceeds; snapshots
are frozen copies that a downstream consumer (a solver, an exporter, an LLM
tool call) can hold and inspect without any risk of touching live state. This
page assumes no prior context beyond `using Delone` — for a shorter, code-only
version of the same material see [Mesh hierarchies & sessions](examples/hierarchy.md).

## Starting a session

[`mesh_session`](@ref) builds a session with a single coarse level and
`generation` starting at `0`:

```@example sessions
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)

s = mesh_session(geom; maxh=0.4)
nlevels(s), generation(s)
```

`geometry(s)` returns the shared geometry backing every level;
`coarsest(s)`/`finest(s)` return live mesh handles for the first/last level;
`level_mesh(s, k)` returns the live handle for level `k`.

## `generation`: the staleness counter

Every mutating **request** — the `request_*!` family — increments
`generation(s)`. This is the mechanism the whole snapshot contract is built
on: a snapshot records the generation it was taken at, and a consumer can
cheaply check whether the live session has moved on since:

```@example sessions
request_uniform_refinement!(s)
nlevels(s), generation(s)
```

`request_uniform_refinement!` appends a new finest level (a uniformly,
geometry-aware refined copy of the previous finest mesh) and preserves every
previous level. `request_marked_refinement!(s, marked)` does the same with
element-wise bisection (`marked` indexed by the **current finest level's**
volume elements). `request_second_order!(s)` is different in kind: it curves
the *current finest* mesh **in place** rather than appending a level — see
the "Same-level, snapshot-invalidating mutation" section below.

## Live handles are expert-only for mutation

`level_mesh(s, k)` returns the real, live Netgen mesh object — not a copy.
Reading from it is always fine. But mutating it directly (`refine!`,
`bisect!`, `make_second_order!`, …) changes the session's state **without**
bumping `generation(s)`, so any snapshot taken beforehand goes silently
stale with no way to detect it. All simulation-time mutation should go
through the `request_*!` functions above.

If you must apply an in-place mutation that isn't one of the `request_*!`
helpers, use [`mutate_level_mesh!`](@ref) to keep generation tracking
correct instead of mutating `level_mesh(s, k)` directly:

```@example sessions
gen_before = generation(s)
mutate_level_mesh!(s, 1) do m
    update_topology!(m)   # any in-place Delone/Netgen call on this level
end
generation(s) == gen_before + 1
```

## Snapshots: copied, consumer-agnostic data

A snapshot is a plain-array copy — coordinates, connectivity, region ids,
names — with **no** live handle inside it. Mutating a snapshot never touches
the session, and the session mutating afterward never touches an
already-taken snapshot (it just makes it stale, see below):

```@example sessions
snap = level_snapshot(s, 1)          # MeshLevelSnapshot for level 1
snap.level, snap.generation, size(snap.coordinates)
```

```@example sessions
ts = transfer_snapshot(s, 2)         # coarse (1) -> fine (2) transition
size(ts.parent_nodes)
```

```@example sessions
hs = hierarchy_snapshot(s)           # every level + every transfer, one call
length(hs.levels), length(hs.transfers)
```

`transfer_snapshot(session, k)` describes the transition **into** level `k`
from level `k - 1`, so `k` must be `≥ 2`; `transfer_snapshot(session, 1)`
throws `ArgumentError` because level 1 has no coarser parent.

### The staleness contract

Every snapshot records `generation(s)` at the moment it was captured. Compare
that recorded value against the session's *current* generation to know
whether the snapshot still describes the live state:

```@example sessions
stale_before = snap.generation != generation(s)
request_uniform_refinement!(s)
stale_after = snap.generation != generation(s)
stale_before, stale_after
```

`snap` above was taken before the second `request_uniform_refinement!`
call, so it is stale afterward — the fix is simply to call
`level_snapshot(s, 1)` again; level 1's own data did not actually change in
this example, but the **contract** is generation-based, not
content-diffed, precisely so a consumer never has to guess whether a
generation bump was "harmless" for their particular level.

### Same-level, snapshot-invalidating mutation

Most `request_*!` functions append a *new* level, so old snapshots of
earlier levels remain valid (their content didn't change, only
`generation` moves on — which is still worth checking, since some
consumers key on "is this the freshest state" rather than "did this
specific level's data change"). `request_second_order!` is different: it
curves the **current finest level in place**:

```@example sessions
gen_before2 = generation(s)
request_second_order!(s)
nlevels(s), generation(s) == gen_before2 + 1
```

- `nlevels(s)` is unchanged — no new level, no h-refinement transfer;
- the finest level's node count increases (projected edge-midpoint nodes)
  and `generation(s)` bumps;
- any snapshot of the finest level taken *before* this call is now stale and
  must be retaken;
- a fresh `level_snapshot` after curving reports the Tet4/Tri3 **corner**
  connectivity — the extra midpoint nodes appear in `coordinates` but are
  not referenced by `volume_connectivity`;
- only `order == 2` is supported; any other value throws `ArgumentError`.

In-place hp/p operations (`request_marked_p_refinement!`,
`request_marked_hp_refinement!`, `request_hp_refine!`,
`request_split_alfeld!`, `request_set_element_orders!`) invalidate
finest-level snapshots the same way.

## `supported_snapshot_topology`

The snapshot contract targets pure simplex meshes only: tetrahedral volume +
triangular boundary in 3D, or triangular domain + segment boundary in 2D.
Curved (second-order) simplices still count as supported, since
`GetNV` still reports 4/3 corners regardless of curving order. Test a mesh
before snapshotting it — a mixed or non-simplex mesh (quads, prisms, hexes)
throws `ArgumentError` rather than being silently reinterpreted:

```@example sessions
supported_snapshot_topology(finest(s))
```

## Transfer weights: `weight_semantics`, not silence

`HierarchyTransferSnapshot.weights` is currently always `nothing` — exact
interpolation weights are not computed yet. This is deliberately **not**
treated as "unknown physical value": the accompanying
`weight_semantics` field states the fallback explicitly:

```@example sessions
ts2 = transfer_snapshot(s, 2)
ts2.weights === nothing, transfer_weight_semantics(ts2)
```

`:topological_bisection_default` means: interpret each new node as the
topological midpoint of its two `parent_nodes` entries (1/2–1/2), i.e. plain
bisection interpolation on the parent-node map — not a numerically weighted
scheme. See [Multigrid hierarchy](reference/hierarchy.md) for
`parent_nodes`/`parent_elements` themselves.

## Stable identity convention

All snapshot ids are one-based; `0` means "none". A parent-node column of
`(0, 0)` marks an **inherited** coarse vertex, and inherited coarse vertices
keep their id on every finer level — so `coordinates(coarse) ≈
coordinates(fine)[:, 1:np_coarse]`. This holds for the current construction
path, where every level refines a copy of the previous finest level.

## Integration contract (summary)

```
Delone.jl provides   live handles, refinement requests, parent maps,
                     region/tag data, copied snapshots, partition hints
Consumer provides    FE spaces, DOFs, operators, estimators, partition policy,
                     multigrid transfer-matrix assembly
```

Next: [Introspection contract](introspection_contract.md) for how a session's
readiness for the next pipeline stage (`OodiImportTarget`,
`GeometricMultigridTarget`) is reported in the same structured, LLM-friendly
style as everything else in this package.
