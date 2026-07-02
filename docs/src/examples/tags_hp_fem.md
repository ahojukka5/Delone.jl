# Tags, hp-adaptivity & FEM data

The examples on this page share one `cylinder.brep` fixture (unit cylinder,
radius 1, height 2) and one running `Delone` session.

## Region ids and names

```@example tags_hp_fem
using Delone

cylinder_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cylinder.brep")
geom = load_brep(cylinder_path)
mesh = generate_mesh(geom; maxh=0.5)

cr = cell_regions(mesh)           # per volume element (3D)
br = boundary_regions(mesh)       # per boundary triangle

mats = material_names(mesh)       # Dict region_id => name (3D)
bnames = boundary_names(mesh)

println("cell_regions: ", length(cr), " elements")
println("boundary_regions: ", length(br), " facets")
println("material_names: ", mats)
println("distinct boundary names: ", unique(values(bnames)))
println("region_name_volume(mesh, 1): ", region_name_volume(mesh, 1))   # per-element material name
println("region_name_surface(mesh, 1): ", region_name_surface(mesh, 1)) # per boundary triangle
```

This fixture has no CAD-authored material/BC names, so every region reports
`"default"` — a realistic outcome for a bare BREP import, not a bug.

**2D caveat:** `material_names` is empty and `boundary_names` keys do not match
`boundary_regions`. Use `region_name_segment(mesh, segnr)` for segment names in 2D.

Codimension dispatch:

```@example tags_hp_fem
println("material_codim_name(mesh, 0, 1): ", material_codim_name(mesh, 0, 1))   # volume material (3D)
println("material_codim_name(mesh, 1, 1): ", material_codim_name(mesh, 1, 1))   # boundary condition name
```

## hp-adaptivity — reading state

```@example tags_hp_fem
println("element_orders (distinct): ", unique(element_orders(mesh)))   # vector length = ncells
println("element_order (max): ", element_order(mesh))
L = hp_element_levels(mesh)              # 3×ncells; -1 = no hp table
println("hp_element_levels all -1 on a fresh mesh: ", all(==(-1), L))

println("surface_element_orders (distinct): ", unique(surface_element_orders(mesh)))  # 3D boundaries only
```

Cluster representatives (only after hp refinement):

```@example tags_hp_fem
println("hp_clusters_available before refinement: ", hp_clusters_available(mesh))
try
    hp_clusters_available(mesh) || error("no hp clusters")
catch e
    println("caught: ", e)
end

mesh_hp = copy_mesh(mesh)
hp_refine!(mesh_hp; levels=1)
println("hp_clusters_available after hp_refine!: ", hp_clusters_available(mesh_hp))
println("cluster_rep_vertices (first 5): ", cluster_rep_vertices(mesh_hp)[1:5])
println("cluster_rep_elements (first 5): ", cluster_rep_elements(mesh_hp)[1:5])
```

## hp-adaptivity — applying changes

On a live mesh (each demonstrated on its own copy, so the operations don't
interfere with each other):

```@example tags_hp_fem
m_orders = copy_mesh(mesh)
set_element_order!(m_orders, 1, 3)                                  # raise order on cell 1
set_element_orders!(m_orders, fill(2, num_cells(m_orders)))         # bulk vector
println("orders after bulk set: ", unique(element_orders(m_orders)))

marked = falses(num_cells(mesh))
marked[1:num_cells(mesh) ÷ 4] .= true

m_p = copy_mesh(mesh)
mark_for_ngx_refinement!(m_p, marked)
ngx_refine!(m_p; reftype=NG_REFINE_P)                                # marked p-refinement
println("cells after marked p-refinement: ", num_cells(m_p))

m_hp = copy_mesh(mesh)
mark_for_ngx_refinement!(m_hp, marked)
ngx_refine!(m_hp; reftype=NG_REFINE_HP)                              # marked hp-refinement
println("cells after marked hp-refinement: ", num_cells(m_hp))

m_global_hp = copy_mesh(mesh)
hp_refine!(m_global_hp; levels=1)                                    # global hp split
println("cells after global hp_refine!: ", num_cells(m_global_hp))

m_alfeld = copy_mesh(mesh)
split_alfeld!(m_alfeld)
println("cells after split_alfeld!: ", num_cells(m_alfeld))
```

Through a session:

```@example tags_hp_fem
s = mesh_session(geom; maxh=0.5)
request_set_element_orders!(s, fill(2, num_cells(finest(s))))
println("orders via session: ", unique(element_orders(finest(s))))

marked_s = falses(num_cells(finest(s)))
marked_s[1:num_cells(finest(s)) ÷ 4] .= true
request_marked_p_refinement!(s, marked_s)
request_hp_refine!(s; levels=1)
nlevels(s)   # in-place hp/p requests do not append a level
```

In-place hp/p operations invalidate finest-level snapshots (same as second-order
curving).

## FEM geometry — curved maps

After `make_second_order!(mesh)`, query reference-to-physical maps:

```@example tags_hp_fem
fem_mesh = generate_mesh(geom; maxh=0.5)
make_second_order!(fem_mesh)

xi = [0.0, 0.0, 0.0]
x, J = volume_element_transformation(fem_mesh, 1, xi)   # 3D volume cell 1
println("x: length ", length(x), ", J: ", size(J))      # x: physical point, J: 3×3 Jacobian

x2, J2 = surface_element_transformation(fem_mesh, 1, [0.0, 0.0])  # 3D boundary
println("x2: length ", length(x2), ", J2: ", size(J2))
```

`domain_element_transformation` is 2D-only, so it needs a 2D mesh:

```@example tags_hp_fem
mesh2d = generate_mesh(geometry2d(Circle(0.0, 0.0, 1.0, "d", "c")); maxh=0.4)
make_second_order!(mesh2d)
x3, J3 = domain_element_transformation(mesh2d, 1, [0.0, 0.0])   # 2D domain
println("x3: length ", length(x3), ", J3: ", size(J3))
```

Batch evaluation:

```@example tags_hp_fem
xis = [0.0 0.5; 0.0 0.0; 0.0 0.0]    # 3×npts
X, Js = volume_element_transformations(fem_mesh, 1, xis)
(size(X), length(Js))
```

## Parent edge / face topology

Off by default. Enable **before** refining:

```@example tags_hp_fem
topo_mesh = copy_mesh(mesh)
enable_topology_table!(topo_mesh, "parentedges")
enable_topology_table!(topo_mesh, "parentfaces")
refine!(topo_mesh)
Delone.Internals.UpdateTopology(topo_mesh)

println("has_parent_edges: ", has_parent_edges(topo_mesh))
ne = num_cells(topo_mesh)
println("parent_edges(mesh, ", ne, "): ", parent_edges(topo_mesh, ne))   # orientation + parent edge indices

# NOTE: in this Netgen build, `parent_faces`'s 2nd–4th return values read
# uninitialized memory when a face has no parent (values vary run to run) —
# only the first field (orientation `info`) is reliable to display here.
println("parent_faces(mesh, 1) info: ", parent_faces(topo_mesh, 1)[1])
println("face_edges(mesh, 1): ", face_edges(topo_mesh, 1))              # needs up-to-date topology
```

## Periodic identifications

```@example tags_hp_fem
println("periodic_vertex_pairs(mesh): ", periodic_vertex_pairs(mesh))       # [] if mesh has no identifications
println("periodic_vertex_pairs(mesh, 1): ", periodic_vertex_pairs(mesh, 1)) # 1-based identification index
```

## Point location & local mesh size

```@example tags_hp_fem
x = points(mesh)[:, 1]
loc = find_element(mesh, x)             # (cell_nr, λ) or nothing
println("find_element found a cell: ", loc !== nothing)
println("mesh_h_at_point(mesh, 1) > 0: ", mesh_h_at_point(mesh, 1) > 0)
```

## Partition hints

Optional input for an external partitioner (METIS/ParMETIS, etc.):

```@example tags_hp_fem
hint = native_partition_hint(mesh)
println("global_vertex_ids: ", length(hint.global_vertex_ids), " entries")   # per local vertex, global id (identity on serial build)
println("distant_procs: ", length(hint.distant_procs), " entries")           # per vertex, remote MPI ranks (empty on serial build)
```

Delone.jl does not call a partitioner or assign ownership.
