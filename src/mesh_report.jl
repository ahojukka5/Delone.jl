# --- combined mesh report ---------------------------------------------------

"""
    MeshReport <: AbstractOodiReport

Combined validation, quality, topology, and tag report for one mesh.
"""
struct MeshReport <: AbstractOodiReport
    validation::MeshValidationReport
    quality::MeshQualityReport
    topology::NamedTuple
    tags::MeshTagReport
end

function Base.show(io::IO, r::MeshReport)
    println(io, "MeshReport")
    println(io, "  ", r.validation)
    println(io, "  ", r.quality)
    println(io, "  topology: dim=", r.topology.dimension,
          ", nodes=", r.topology.node_count,
          ", cells=", r.topology.element_count)
    print(io, r.tags)
end

function Base.summary(io::IO, r::MeshReport)
    print(io, "MeshReport(dim=", r.topology.dimension,
          ", nodes=", r.topology.node_count,
          ", cells=", r.topology.element_count,
          ", valid=", r.validation.valid, ")")
end

function Base.show(io::IO, ::MIME"text/html", r::MeshReport)
    print(io, "<div class=\"delone-report\"><b>MeshReport</b>",
          "<table>",
          "<tr><th>dimension</th><td>", r.topology.dimension, "</td></tr>",
          "<tr><th>nodes</th><td>", r.topology.node_count, "</td></tr>",
          "<tr><th>cells</th><td>", r.topology.element_count, "</td></tr>",
          "<tr><th>valid</th><td>", r.validation.valid, "</td></tr>",
          "<tr><th>min_quality</th><td>", round(r.quality.min_quality; digits=4), "</td></tr>",
          "<tr><th>boundary tags</th><td>", length(r.tags.boundary_tags), "</td></tr>",
          "<tr><th>region tags</th><td>", length(r.tags.region_tags), "</td></tr>",
          "</table></div>")
end

"""
    mesh_report(mesh) -> MeshReport

One-call structured mesh summary for LLM feedback loops.
"""
function mesh_report(m)
    return MeshReport(
        validate(m),
        quality(m),
        topology_report(m),
        tag_report(m))
end
