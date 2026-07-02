# Development

## Prerequisites

- Julia ≥ 1.9 (required for the `Base.get_extension` package-extension
  mechanism used by `DeloneMakieExt`/`DeloneWriteVTKExt`/`DeloneGeometryBasicsExt`)
- CMake and a C++17 compiler
- Artifacts: `NGSolveNetgen_jll`, `OCCT_jll` (BREP bridge), `libcxxwrap-julia`
- For BREP interop tests: sibling `OpenCascade.jl` (auto-`Pkg.develop` from `test/runtests.jl`)

Build OpenCascade's wrapper first if testing CAD interop:

```julia
julia --project=../OpenCascade.jl ../OpenCascade.jl/gen/build_local.jl
```

`NetgenCxxWrap_jll` is not registered in General yet; the native wrapper library
is built locally and pinned in `Artifacts.toml`.

## Build the native library

From the `Delone.jl` package directory:

```julia
julia --project=. gen/build_local.jl
```

This configures and compiles `libnetgen_cxxwrap`, then updates `Artifacts.toml`
with the local artifact hash. Re-run after changing `NetgenCxxWrap_jll/bundled/`.

## Run tests

```julia
julia --project=. test/runtests.jl
```

Tests need the built artifact and fixture files under `test/fixtures/`.

## Build this documentation

```julia
julia --project=docs docs/make.jl
```

Output lands in `docs/build/`. Open `docs/build/index.html` in a browser.

The `docs` environment depends on the parent package (`Delone = {path = ".."}` in
`docs/Project.toml`). Instantiate once:

```julia
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
```

## Repository layout

| Path | Role |
|------|------|
| `Delone.jl/src/` | Julian layer + `include` of helper modules |
| `Delone.jl/gen/build_local.jl` | Local CxxWrap build script |
| `NetgenCxxWrap_jll/bundled/src/` | Netgen 1:1 C++ wrappers + `netgen_occ_bridge.cpp` |
| `OpenCascadeCxxWrap_jll/bundled/src/` | OCCT 1:1 C++ wrappers (`occ_*.cpp`) |
| `OpenCascade.jl/` | CAD modeling Julia package |
| `netgen/` (sibling repo) | Upstream reference — **do not patch** |
| `NGSolveNetgen_jll/` | Upstream JLL reference — **do not patch** |

## Adding new bindings

1. Add strict 1:1 wrapper in `NetgenCxxWrap_jll/bundled/src/`.
2. Register in the appropriate `register_*` function and `CMakeLists.txt`.
3. Rebuild with `gen/build_local.jl`.
4. Add Julian helper (if needed) in `Delone.jl/src/`.
5. Add tests under `Delone.jl/test/`.
6. Update `docs/API_COVERAGE.md` and these docs.

Policy: **no convenience combinators in C++**; composition stays in Julia.

## Deploying docs

`.github/workflows/docs.yml` already builds the docs (with doctests) on every
push/PR and calls `deploydocs()`; `deploydocs()` only actually publishes when
it detects a real CI deploy context, so it safely no-ops on PR builds and
local runs. The one remaining manual step is adding a `DOCUMENTER_KEY` repo
secret (an SSH deploy key generated via `DocumenterTools.genkeys(...)` or the
GitHub App) — until that's added, the build/doctest step still runs but the
deploy step skips publishing.
