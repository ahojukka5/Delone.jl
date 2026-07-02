# Mesh generation & I/O

Building [`MeshOptions`](@ref), generating meshes from geometry, and
loading/saving meshes to disk.

```@docs
MeshOptions
mesh_options
validate_options!
to_meshing_parameters
meshing_parameters
generate_mesh
generate_mesh_result
try_generate_mesh
MeshGenerationResult
MeshGenerationDiagnostics
generated_mesh
mesh
save_mesh
load_mesh
update_topology!
compress!
mesh_from_arrays
add_volume_element!
add_surface_element!
```

## Alternative backend: Gmsh

Optional — active once the registered `Gmsh` package is loaded (see
[Building geometry](@ref "Building geometry") for a worked example and
[Package extensions](@ref "Package extensions") for the general mechanism).

```@docs
generate_gmsh_mesh
```
