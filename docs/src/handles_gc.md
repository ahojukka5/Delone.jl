# Handle lifetimes, ownership, and garbage collection

Delone.jl's live mesh and geometry objects are C++ objects managed by
[CxxWrap](https://github.com/JuliaInterop/CxxWrap.jl) and reachable from
ordinary Julia structs — a [`MeshHierarchySession`](@ref) holds `meshes::
Vector{Any}`, a [`MeshHierarchy`](@ref) holds the same shape. This page
explains what that means for object lifetimes: when a handle is safe to keep
around, what happens if you extract one and let its owning struct go out of
scope, and how this contrasts with snapshots, which have no such lifetime
concern at all. None of this is documented anywhere else in the package
today, so treat this page as the canonical source.

## The basic guarantee: reachability keeps handles alive

Julia's garbage collector works by reachability: an object is kept alive as
long as something reachable from a GC root still refers to it. A
`MeshHierarchySession`'s `meshes` field is an ordinary `Vector{Any}` of
CxxWrap-wrapped mesh objects, so as long as the session struct itself is
reachable, every mesh handle inside it is reachable too, and none of them
will be finalized:

```@example handles_gc
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)

s = mesh_session(geom; maxh=0.4)
request_uniform_refinement!(s)
nlevels(s)
```

As long as `s` stays reachable (a global binding, a field of another live
struct, a local variable still in scope), `level_mesh(s, 1)` and
`level_mesh(s, 2)` stay valid to call into. This is the ordinary case and
requires no special care.

## What if you extract a handle and drop the session?

This is the question worth answering explicitly, because it is not obvious
from the API alone whether a live mesh handle's validity is somehow tied to
its *session*, the way a raw pointer might be invalidated once the object
that allocated it is destroyed. It is not: the object returned by
`level_mesh(s, k)` is a first-class Julia value (a CxxWrap wrapper around a
`shared_ptr<Mesh>`), and once you hold *your own* reference to it, that
reference — not the session's `Vector{Any}` — is what keeps it reachable.
Empirically:

```@example handles_gc
function make_handle_and_drop_session()
    session = mesh_session(geom; maxh=0.4)
    handle = level_mesh(session, 1)   # extract the live mesh handle
    return handle                     # `session` becomes unreachable on return
end

m = make_handle_and_drop_session()
GC.gc(true)
GC.gc(true)
num_nodes(m)   # still callable after the owning session is gone and GC has run
```

The mesh handle **survives** the session going out of scope, and forcing a
full garbage collection does not finalize or invalidate it. `num_nodes(m)`
above is a real call into the live Netgen mesh, not a cached value — it
succeeds because the underlying `shared_ptr<Mesh>` is still referenced by
the Julia wrapper object `m`, and `m` is reachable from the local binding in
this scope regardless of what happened to `session`.

**Do not read this as "sessions don't matter for lifetime management."**
What it means precisely is: Julia's GC tracks reachability of the *handle
object itself*, not of the *session struct that happened to hand it to
you*. If you extract a handle and keep a reference to it (in a variable, a
field, a closure), it stays alive on its own merits. If you extract a
handle and *do not* keep any reference to it — and the session that held it
is also unreachable — then, like any other Julia value, it becomes eligible
for collection and its finalizer runs. The session is not adding or
removing protection from the handle; each Julia binding to the same
underlying object independently keeps it alive.

## Practical implication

This means the `Vector{Any}` inside a session is not a special ownership
mechanism you need to defeat or work around — it is just one more reference
among potentially several. In practice this makes handle lifetimes in
Delone.jl behave the way most Julia objects do (no manual `delete`/`free`,
no dangling-pointer class of bug from normal use), which is a meaningfully
different — and safer — situation than working with raw C++ pointers
directly. That said, this package makes no *documented upstream guarantee*
about `Internals`' CxxWrap-generated finalizers beyond ordinary Julia GC
semantics — see "Open question" below before relying on this for anything
safety-critical (e.g. holding a handle across a long-running external
process boundary, or assuming finalization order relative to the geometry
object a mesh depends on).

## Contrast: snapshots have no lifetime concern at all

Everything above is about **live handles**. Snapshots
([`MeshLevelSnapshot`](@ref), [`HierarchyTransferSnapshot`](@ref),
[`MeshHierarchySnapshot`](@ref), produced by [`level_snapshot`](@ref),
[`transfer_snapshot`](@ref), [`hierarchy_snapshot`](@ref)) are different in
kind, not just in degree: they are copied plain Julia arrays
(`Matrix{Float64}`, `Matrix{Int32}`, `Dict{Int32,String}`, …) with no C++
object inside them at all.

```@example handles_gc
snap = level_snapshot(s, 1)
typeof(snap.coordinates), typeof(snap.volume_connectivity)
```

A snapshot has completely ordinary Julia value semantics: no finalizer, no
underlying native resource, nothing that becomes invalid when any other
object is garbage collected. You can hold a snapshot indefinitely, serialize
it, send it across a process boundary, or let the session (and every live
handle it ever held) be fully collected — the snapshot is unaffected,
because it never referenced the live handle to begin with; `level_snapshot`
*read from* the live mesh once, at capture time, and copied everything it
needed into plain arrays. This is precisely why the [live-session
staleness contract](sessions_snapshots.md) exists as a *generation counter*
rather than a live reference: a snapshot cannot "point at" a session in any
GC sense, so the only way to know it might be out of date is to compare the
recorded `generation` against the session's current one.

## Open question: are `Internals`' finalizers documented upstream?

No — as far as this repository's documentation goes, this is unverified.
Neither [`docs/API_COVERAGE.md`](https://github.com/ahojukka5/Delone.jl/blob/master/docs/API_COVERAGE.md)
nor [`AGENTS.md`](https://github.com/ahojukka5/Delone.jl/blob/master/AGENTS.md)
makes any claim about how `NetgenCxxWrap_jll`'s CxxWrap-generated bindings
finalize their underlying C++ objects (destructor ordering between a mesh
and the geometry it was built from, thread-safety of finalizers, behavior
under `Base.@ccallable` boundaries, or anything else beyond what CxxWrap
provides by default for `shared_ptr`-wrapped types). The empirical behavior
demonstrated above — a `shared_ptr<Mesh>`-backed handle surviving its
originating session and an explicit `GC.gc(true)` — is consistent with
CxxWrap's default `shared_ptr` finalizer behavior, but this page is
reporting an observation from this package's build, not citing an upstream
guarantee. If you need a stronger guarantee than "matches observed
behavior in this build," treat it as an open item to verify against
CxxWrap.jl's own documentation rather than an assumption this package makes
for you.

Next: [Sessions & snapshots](sessions_snapshots.md) for the generation/staleness
contract this page's snapshot contrast leans on, and [Internals escape
hatch](internals_escape_hatch.md) for when you need to reach into
`Delone.Internals` directly.
