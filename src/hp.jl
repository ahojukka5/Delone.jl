# --- hp-adaptivity readiness -------------------------------------------------
# Julia-friendly readers over the wrapped Netgen hp/order accessors. These are
# READ-ONLY (readiness): a consumer can later ask what orders/hp-levels exist per
# element. Applying per-element p-refinement needs the exported Netgen setters
# (`SetElementOrder`, …) wrapped 1:1 — see the audit doc (§5). No hp *strategy*
# is implemented here.
#
# Indexing conventions (verified against netgen/libsrc/interface/nginterface_v2.cpp):
#   GetElementOrder(enr) / GetElementOrders(enr,…) / GetSurfaceElementOrder(enr):
#       enr is 1-based.
#   GetHPElementLevel(ei, dir): ei is 0-based (upstream does ei++); dir ∈ {1,2,3};
#       returns -1 when the mesh has no hp-element table.

"""
    element_orders(mesh) -> Vector{Int}

Per top-dimensional cell polynomial order (`Ngx_Mesh::GetElementOrder`, 1-based
enr; uses volume elements in 3D, triangles in 2D). Length is `GetNE` (3D) or
`GetNSE` (2D). A freshly generated linear mesh returns all `1`.
"""
function element_orders(m)
    nm = Ngx_Mesh(m)
    return Int[GetElementOrder(nm, i) for i in 1:_ncells(m)]
end

"""
    element_order(mesh) -> Int

The mesh's representative polynomial order: `maximum(element_orders(mesh))`
(`1` for an empty mesh). Convenience summary of [`element_orders`](@ref).
"""
function element_order(m)
    os = element_orders(m)
    return isempty(os) ? 1 : maximum(os)
end

"""
    surface_element_orders(mesh) -> Vector{Int}

Per boundary triangle polynomial order (`Ngx_Mesh::GetSurfaceElementOrder`,
1-based). **3D only** — errors with `ArgumentError` otherwise (2D boundary
facets are segments and have no order accessor through this API). Length `GetNSE`.
"""
function surface_element_orders(m)
    d = GetDimension(m)
    d == 3 || throw(ArgumentError(
        "surface_element_orders requires a 3D mesh (got dim=$d); " *
        "2D boundary segments have no order accessor"))
    nm = Ngx_Mesh(m)
    return Int[GetSurfaceElementOrder(nm, i) for i in 1:GetNSE(m)]
end

"""
    surface_element_order(mesh) -> Int

Representative boundary polynomial order: `maximum(surface_element_orders(mesh))`.
3D only.
"""
function surface_element_order(m)
    os = surface_element_orders(m)
    return isempty(os) ? 1 : maximum(os)
end

"""
    hp_element_levels(mesh) -> 3×ncells Matrix{Int}

Per cell, its hp-refinement level in each direction `(x, y, z)`
(`Ngx_Mesh::GetHPElementLevel`, 0-based element query internally). Columns index
cells 1-based. Returns `-1` entries when the mesh carries no hp-element table
(i.e. it has not been hp-refined) — this is Netgen's own sentinel, surfaced
as-is; it is not an error.
"""
function hp_element_levels(m)
    nm = Ngx_Mesh(m)
    nc = _ncells(m)
    L = Matrix{Int}(undef, 3, nc)
    for i in 1:nc
        for dir in 1:3
            L[dir, i] = GetHPElementLevel(nm, i - 1, dir)
        end
    end
    return L
end
