# Changelog

All notable changes to Delone.jl are documented in this file.

## [Unreleased]

### Added (roadmap Phase 2 — functionality gaps)
- **Local mesh sizing** (`src/local_sizing.jl`): `LocalSizeField`,
  `local_size_field`, `restrict_h!`, `restrict_h_at!`, `mesh_h_at`,
  `set_global_h!`, `set_minimal_h!`, `refine_near!`, and a `local_size` option
  on `MeshOptions`. Netgen's `RestrictLocalH`/`SetLocalH` were investigated
  and found not to feed back into `generate_mesh` in this build, so local
  sizing is implemented as coarse generation followed by geometric
  mark-and-bisect refinement near the requested points — verified to work in
  3D; in 2D `bisect!` refines uniformly regardless of marking, so
  `local_size` only achieves uniform refinement there (documented, warned).
- **Native Netgen quality diagnostics**: `NativeQualityReport`,
  `native_quality`, and new `netgen_*`-prefixed fields on `MeshQualityReport`
  (`CalcTotalBad`/`ElementError`-based, distinct scale from the existing
  Julia-side proxy metrics — see the docstring). `suggest_mesh_fixes` now
  surfaces orientation/boundary/overlap issues Netgen's own kernel detects.
  `FindOpenElements`/`FindOpenSegments` were investigated and found not
  exposable as a count with the current C++ bindings (documented as an open
  item needing new bindings, not faked).
- **Pre-meshing boundary/material naming**: `set_material_name!`,
  `set_boundary_name!`, `rename_materials!`, `rename_boundaries!` in
  `src/tags.jl` — the write side of the existing `material_names`/
  `boundary_names` queries.
- New API reference page `docs/src/reference/local_sizing.md`, and additions
  to `reference/validation_quality.md` / `reference/tags.md`.

### Investigated, not shipped
- `STLParameters` (STL feature-angle meshing controls): confirmed
  unreachable from the wrapped `STLGeometry::GenerateMesh` — it copies a
  global C++ singleton rather than accepting a caller-supplied object, and
  the lower-level free function that would (`STLMeshingDummy`) isn't exposed
  by `NetgenCxxWrap_jll`. No `STLOptions` API was added; needs a new C++
  binding upstream first.

### Known bug found (not yet fixed)
- `generate_mesh`/`generate_mesh_result` is broken end-to-end for STL
  geometry: `Internals.SetGeometry` has no overload accepting `STLGeometry`
  (only `NetgenGeometry`), so it throws `MethodError` before meshing starts.
  Calling `Internals.GenerateMesh` directly (skipping `SetGeometry`) works.

### Added
- Full Documenter.jl API reference (`docs/src/reference/*.md`, 13 pages,
  `@docs` blocks grouped by topic to match `src/Delone.jl`'s export sections)
  wired into `docs/make.jl`'s page tree.
- `checkdocs = :exported` in `docs/make.jl`, so an exported name with no
  docstring now fails/warns the docs build instead of going unnoticed.
- `LICENSE` (MIT) and this `CHANGELOG.md`.
- CI workflows: `.github/workflows/test.yml` and `.github/workflows/docs.yml`
  (best-effort first pass — not yet validated on a real GitHub Actions
  runner; see caveats in each file, notably that `gen/build_local.jl` expects
  a sibling `NetgenCxxWrap_jll` checkout CI does not fetch).
- `Aqua.jl` static-quality testset in `test/runtests.jl` (ambiguities,
  stale-deps, and piracy checks disabled with documented reasons — CxxWrap
  method tables, this repo's monorepo-style dependency convention, and the
  intentional OodiCore introspection-contract extension pattern,
  respectively; unbound-args and undefined-exports checks pass and stay on).
- Missing docstrings for several exported names (`src/constants.jl`,
  `src/geometry.jl`'s `load_*` family, `src/hierarchy.jl`'s
  `level_nvertices`/`coarsest`/`finest`/`geometry`/`uniform_hierarchy`/
  `refine_uniform!`/`refine_marked!`/`prolongation`).

### Changed
- Consolidated redundant naming (deprecated via `Base.@deprecate`, old names
  still callable with a warning): `try_generate_mesh` → `generate_mesh_result`,
  `coarse_hierarchy` → `mesh_hierarchy(geom; maxh=maxh)`, `mesh_quality` →
  `quality`. The legacy `secondorder` keyword to `mesh_options` now emits a
  deprecation warning pointing at `second_order` instead of being silently
  accepted.
- `Manifest.toml` is no longer tracked in git (library convention).
- Renamed the package from `Netgen.jl` to `Delone.jl`; `Delone.Internals` is
  the raw `NetgenCxxWrap_jll` escape hatch (Netgen/NGSolve remains the backend
  engine name throughout). See `audit/DELONE_REBRAND_AND_LLM_MESHING_VISION_2026-07-02.md`.
- Split the former monolithic `src/Netgen.jl` into focused modules
  (`geometry.jl`, `mesh.jl`, `options.jl`, `validation.jl`, `quality.jl`,
  `refinement.jl`, `hierarchy.jl`, `session.jl`, `snapshots.jl`, `hp.jl`,
  `fem.jl`, `export_mesh.jl`, `introspection.jl`, and structured report types).

## [0.1.0]

Initial development version. Julian, LLM-friendly meshing, refinement,
mesh-diagnostics, and mesh-hierarchy API built on Netgen/NGSolve
(`Delone.Internals` — raw `NetgenCxxWrap_jll` bindings). See `README.md` and
`AGENTS.md` for the introspection contract and architecture.
