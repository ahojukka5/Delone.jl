# Refinement

Delone.jl supports **uniform**, **marked adaptive**, and **second-order**
refinement. All h-refinement paths are **geometry-aware**: new boundary nodes are
projected onto the true curved boundary (circle, sphere, CAD face), not placed at
chord midpoints.

## Uniform refinement

```@example refinement
using Delone

geom = geometry2d(Circle(0.0, 0.0, 1.0, "d", "c"))
mesh = generate_mesh(geom; maxh=0.4)

# NOTE: `Internals.GetNE` counts *volume* elements and is always 0 for a 2D
# mesh — 2D domain triangles are stored as surface elements. Use `GetNSE`
# (or the dimension-aware `num_cells`) for 2D cell counts.
nc0 = Delone.Internals.GetNSE(mesh)
refine!(mesh)                    # in place
Delone.Internals.GetNSE(mesh) > nc0        # more elements
```

On a 3D cylinder built from BREP, boundary vertices stay on the curved lateral
surface after `refine!` (radius 1 within floating-point tolerance) — the same
geometry-aware projection applies to any curved CAD face, not just 2D circles.

## Marked bisection (adaptive)

Mark elements, then bisect:

```@example refinement
mesh2 = generate_mesh(geom; maxh=0.4)
Delone.Internals.UpdateTopology(mesh2)

nc = Delone.Internals.GetNSE(mesh2)   # 2D domain triangles, see note above
marked = falses(nc)
marked[1:nc÷4] .= true            # refine first quarter of elements

mark_for_refinement!(mesh2, marked)
bisect!(mesh2)
Int(num_cells(mesh2))
```

**2D caveat:** [`mark_for_refinement!`](@ref) only sets flags on **3D volume**
elements (`Internals.GetNE`/`VolumeElement`); on a 2D mesh it is a no-op, and
Netgen's 2D bisection then refines **uniformly** regardless of marking — the
block above quadruples the element count exactly, not just the marked quarter.
For real element-wise adaptivity in 2D, mark with
[`mark_for_ngx_refinement!`](@ref) and refine with [`ngx_refine!`](@ref) instead
(see [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")) —
that path does produce a genuinely localized element count increase, and is
exactly what [`refine_near!`](@ref)/`MeshOptions.local_size` use for their 2D
path (see [Local mesh sizing](@ref)) precisely because of this caveat. In 3D,
`mark_for_refinement!` + `bisect!` performs true localized bisection.

`BisectionOptions` fields (`refine_p`, `refine_hp`, …) are available on the C++
type if you need marked p- or hp-refinement at the bisection step; Julian session
helpers wrap the common cases (see [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")).

## Second-order curving

Add edge midpoints and curve them onto the geometry:

```@example refinement
np0 = Delone.Internals.GetNP(mesh)
make_second_order!(mesh)
Delone.Internals.GetNP(mesh) > np0         # new midpoint nodes
```

Second-order curving is **in-place** on the same mesh level: it does not append a
new multigrid level (unlike `refine!`). Snapshots of that level must be refreshed
after curving (`generation` changes in a live session).

## Parent nodes after refinement

`parent_nodes(mesh)` returns a `2×np` matrix: for each fine node, the two coarse
parent node indices (or `(0,0)` if the node existed on the coarse mesh with the
**same index**):

```@example refinement
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)

P = parent_nodes(fine)
Xc, Xf = points(coarse), points(fine)

for j in axes(P, 2)
    a, b = P[1, j], P[2, j]
    a == 0 && continue
    # New node j splits edge (a,b) on the coarse mesh; Xf[:,j] is on the geometry.
end

n_new = count(j -> P[1, j] != 0, axes(P, 2))
(n_new, size(P, 2))
```

On a unit disk, parents on the boundary lie at radius 1, the chord midpoint sits
inside (`r < 1`), but the new node is projected back to `r = 1`.

## Low-level refinement API

The 1:1 stack is:

```
GetGeometry(mesh) → GetRefinement(geom) → Refine / Bisect / MakeSecondOrder
```

`refine!`, `bisect!`, and `make_second_order!` are thin wrappers around that
chain.

Next: [Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions") for multi-level workflows and snapshot
export.
