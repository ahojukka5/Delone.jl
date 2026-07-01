# Tags & regions

Mapping mesh cells and boundary facets to their Netgen region ids, and those
ids to human-readable material/boundary-condition names.

```@docs
cell_regions
boundary_regions
material_names
boundary_names
region_name_volume
region_name_surface
region_name_segment
material_codim_name
```

## Naming setters

Write side of `material_names`/`boundary_names`, for naming boundaries and
materials on an already loaded/generated mesh.

```@docs
set_material_name!
set_boundary_name!
rename_materials!
rename_boundaries!
```
