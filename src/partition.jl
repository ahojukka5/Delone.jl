# --- partitioning / load-balancing data contract ----------------------------
# Netgen.jl does NOT own domain decomposition. It only exposes stable
# mesh/hierarchy/tag data (see snapshots.jl, tags.jl) so a consumer can build a
# PartitionGraph and call METIS/ParMETIS-style backends itself. No METIS /
# ParMETIS is called here, and no partition policy lives here.

"""
    native_partition_hint(mesh) -> Nothing

Optional native partition hint from Netgen. Returns `nothing` for the current
(serial) build: Netgen's exported partition data
(`Ngx_Mesh::GetDistantProcs`, `Ngx_Mesh::GetGlobalVertexNum`) is MPI-only and is
not wrapped, so there is no native serial partition array to expose. This absence
is reported honestly rather than fabricated.

When an MPI-enabled artifact and the two strict-1:1 bindings exist, this may
return per-node distant-proc / global-id data as **optional** input to a
consumer's partitioner. It must never encode a partitioning *policy* — the
consumer owns `PartitionGraph`, weights, METIS/ParMETIS backend selection,
`PartitionAssignment`, ownership, ghost/halo construction, repartitioning and
migration.
"""
native_partition_hint(m) = nothing
