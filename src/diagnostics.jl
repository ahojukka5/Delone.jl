# --- shared diagnostic message types ----------------------------------------
# DiagnosticMessage is owned by OodiCore (see AGENTS.md / ../OodiCore.jl); this
# file only adds the small `_diagnostic`/`_append!` convenience wrappers used
# throughout the local reports, mapping this package's category vocabulary
# (:error, :warning, :info, :suggestion) onto OodiCore's three severities.
# `:suggestion` maps to severity `:info` — the distinction from a plain info
# message is carried by which report field it lives in (a `suggestions` vector).

function _diagnostic(category::Symbol, code::Symbol, message::AbstractString)
    category === :error && return error_diagnostic(code, message)
    category === :warning && return warning(code, message)
    (category === :info || category === :suggestion) && return info(code, message)
    throw(ArgumentError("unknown diagnostic category :$category"))
end

function _append!(msgs::Vector{DiagnosticMessage}, category::Symbol, code::Symbol, message::AbstractString)
    push!(msgs, _diagnostic(category, code, message))
    return msgs
end

# --- HTML escaping for MIME"text/html" show methods -------------------------
# Small dependency-free helper shared by the report `show(::MIME"text/html", ...)`
# methods across the report files (mesh_report.jl, hierarchy_report.jl,
# quality.jl, validation.jl, generation_result.jl, refinement_result.jl,
# meshability.jl, oodi_readiness.jl, tag_report.jl). Any string field that can
# contain user-controlled text (diagnostic messages, boundary/material names)
# must be passed through this before interpolation into HTML.
"""Escape `&`, `<`, `>` for safe interpolation into a `MIME"text/html"` snippet."""
function _html_escape(s::AbstractString)
    s = replace(s, '&' => "&amp;")
    s = replace(s, '<' => "&lt;")
    s = replace(s, '>' => "&gt;")
    return s
end
_html_escape(x) = _html_escape(string(x))
