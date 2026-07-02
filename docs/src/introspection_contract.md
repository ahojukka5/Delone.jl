# The introspection contract: `report` / `validate` / `readiness`

Delone.jl is designed to be **LLM-native** — this is an architecture
principle stated in [`AGENTS.md`](https://github.com/ahojukka5/Delone.jl/blob/master/AGENTS.md),
not a cosmetic feature. This page is the conceptual explainer of *why* that
contract exists and *how* a tool-calling agent should use it. For a
code-first walkthrough of the same functions, see
[Structured reports & introspection](examples/introspection.md); this page
explains the design behind that page's examples.

## Why this exists

A meshing library's natural failure mode, from an agent's point of view, is
opacity: a function returns a raw handle, or throws an unstructured error,
and the caller — human or LLM — has no principled way to ask "what did I just
get?", "is it usable?", or "is it good enough for what I want to do next?".
Delone.jl's public objects are designed to answer those questions directly
instead of forcing every caller to re-derive them from scratch by poking at
`Delone.Netgen`.

The contract is deliberately **read-only**. `report`, `validate`, and
`readiness` never mutate the object they inspect — mutation always goes
through an explicit `!`-suffixed function (`refine!`, `repair!`,
`request_*!`, …). This separation matters in practice: read-only
introspection can eventually be exposed as freely-callable agent tools
without any dry-run or sandboxing machinery, while mutating operations
cannot.

## Three verbs, three different questions

```julia
report(x)              # "What is this object?"
validate(x)            # "Is this object internally valid?"
readiness(x, target)   # "Can this object move to the requested next stage?"
```

- **`report(x)`** is the main structured-introspection entry point: key
  metadata, dimensions/counts/options, warnings, diagnostics, references to
  artifacts. It is what you reach for first when you just want to know what
  something is.
- **`validate(x)`** checks *internal* consistency only — missing data,
  inconsistent topology, invalid option combinations, unresolved tags,
  unsupported element types. It says nothing about fitness for any
  particular downstream use.
- **`readiness(x, target)`** checks fitness for a *specific* next pipeline
  stage. Validity is necessary but not sufficient: a mesh can be perfectly
  well-formed and still be unfit for a target stage.

Keep the distinction sharp with the canonical example from `AGENTS.md`:
`validate(mesh).valid == true` can hold while `readiness(mesh,
OodiImportTarget())` still fails, because the mesh's element type is
unsupported by the Oodi snapshot contract even though the mesh itself is
perfectly valid. Concretely:

```@example introspection_contract
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)
mesh = generate_mesh(geom; maxh=0.4)

validate(mesh).valid
```

```@example introspection_contract
readiness(mesh, OodiImportTarget()).ready
```

Both are `true` here because a plain 2D triangle mesh is both valid and
snapshot-ready — but the two checks are answering different questions, and on
a mesh with an unsupported topology (quads, prisms, mixed elements) the first
would still say `true` while the second would say `false`, with the
`warnings` field explaining exactly why.

## Which object types support which verbs today

This is a living contract — `AGENTS.md` explicitly tracks it as "current
state, do not over-claim" and grows it incrementally. As of this page:

| Contract role | Generic verb | Delegates to / notes |
|---------------|--------------|----------------------|
| `report(x)` | `report(mesh)`, `report(::MeshHierarchy/Session)`, `report(::MeshGenerationResult/RefinementResult)` | wraps [`mesh_report`](@ref) / [`hierarchy_report`](@ref); results return themselves |
| `validate(x)` | `validate(mesh)` → `MeshValidationReport`; `validate(::MeshOptions)` → `OodiCore.ValidationReport` | [`isvalid`](@ref) shortcut; geometry `validate` still TODO |
| `readiness(x, target)` | [`MeshingTarget`](@ref), [`OodiImportTarget`](@ref), [`GeometricMultigridTarget`](@ref) | delegate to [`meshability_report`](@ref) / [`oodi_snapshot_readiness`](@ref) / `OodiCore.ReadinessReport` |
| serialization | [`to_namedtuple`](@ref)`(report)` | recursive, JSON-friendly; never emits raw handles |
| structured results | [`MeshGenerationResult`](@ref), [`RefinementResult`](@ref), [`MeshQualityReport`](@ref), [`MeshTagReport`](@ref), `OodiSnapshotReadiness`, [`MeshabilityReport`](@ref), `DiagnosticMessage` | printable structs with fields |

Notably still open: `validate` does not yet cover raw geometry handles (there
is no stable dispatch type for a bare Netgen geometry pointer yet), and
`readiness(mesh, DiscretizationTarget)` awaits Oodi.jl defining its own
requirements. If you are extending this package and need one of these, check
`AGENTS.md`'s "TODO: converge on the introspection contract" section first —
it is the authoritative running list.

### `report`/`validate`/`readiness` are owned by OodiCore, not Delone

The generic functions themselves, the `DiagnosticMessage` type, and the base
marker/report types (`AbstractPipelineTarget`, `PipelineTarget`,
`ValidationReport`, `ReadinessReport`, `ObjectReport`, `ArtifactRef`) are
defined once in **OodiCore.jl**, a small shared contract package used across
the whole Monge → Delone → Oodi ecosystem. Delone.jl only *adds methods* on
those generics (in `src/introspection.jl`) and defines its own concrete
report types (`MeshReport`, `MeshHierarchyReport`, `MeshabilityReport`,
`OodiSnapshotReadiness`, …) and target markers (`MeshingTarget`,
`OodiImportTarget`, `GeometricMultigridTarget`, all `<: AbstractPipelineTarget`).
This is why `readiness(x, target)` dispatches cleanly across packages without
name collisions, and why a sibling package can add its own target types
(e.g. a future `DiscretizationTarget` from Oodi.jl) without touching
Delone.jl at all.

Unsupported `(object, target)` combinations throw a clear `ArgumentError`
rather than silently returning a meaningless report:

```@example introspection_contract
try
    readiness(geom, MeshingTarget())   # missing required options=
catch err
    err
end
```

## How a tool-calling agent should use this

`AGENTS.md`'s "MCP / tool-server direction" section states the intended
end state plainly: this contract should be exposable through an MCP server
or similar tool interface (`oodi.report`, `oodi.validate`, `oodi.readiness`)
with almost no adaptation. That constrains the design in ways worth knowing
if you are building a tool-calling agent against this package today, ahead
of any formal server existing:

- **Inputs are schema-friendly.** `readiness(x, target)` takes a small,
  serializable target marker (`MeshingTarget(options=...)`,
  `OodiImportTarget()`, `GeometricMultigridTarget()`) rather than an
  open-ended keyword bag, so a tool schema can enumerate the valid targets.
- **Outputs are structured, not strings.** Every report is a Julia struct
  with named fields and a recursive [`to_namedtuple`](@ref) conversion —
  the natural shape for a JSON tool-call response. Raw Netgen/`Netgen`
  handles are never serialized; a `MeshGenerationResult`, for instance,
  reports `has_mesh`, `node_count`, `cell_count` instead of embedding the
  live mesh object.
- **Artifacts are referenced, not embedded.** When a report needs to point
  at an exported file (VTK/OBJ/SVG preview), it does so via a path-like
  reference, not by inlining the mesh itself.
- **Read-only stays separate from mutating.** Because `report`/`validate`/
  `readiness` cannot change state, an agent framework can expose them as
  always-safe-to-call tools while gating `refine!`/`request_*!`/`solve!`
  behind confirmation or sandboxing — the split already exists in the API,
  it does not need to be bolted on at the tool-server layer.

A practical pattern for an agent driving this package end to end: call
`readiness(geom, MeshingTarget(options=opts))` before committing to a
potentially expensive `generate_mesh` call; call `mesh_report(mesh)` (or the
generic `report(mesh)`) after generation to decide whether to proceed,
retry with different options, or surface a failure; call `readiness(h,
GeometricMultigridTarget())` before handing a hierarchy off to a multigrid
solver. None of these calls require understanding Netgen's C++ API, and none
of them can accidentally mutate the mesh or hierarchy being inspected.

## Extending the contract

If you are adding a new major object to this package, `AGENTS.md` spells out
the expectations directly — the short version: give it a `report`, plan its
`validate` and `readiness` methods (even if not implemented on day one),
keep reports as structured Julia objects with readable `show` methods, never
silently swallow a failure mode (surface it as a warning or an explicit
"not implemented" instead), and prefer extending these three generics over
inventing a new ad-hoc print/debug helper.

Next: [Structured reports & introspection](examples/introspection.md) for the
full worked code walkthrough (`mesh_report`, `meshability_report`,
`hierarchy_report`, `to_namedtuple`, export/preview formats) that this page
has been building the conceptual case for.
