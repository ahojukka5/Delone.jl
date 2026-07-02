# Base-interface polish: MeshHierarchySnapshot collection contract, Base.summary
# one-liners, and MIME"text/html" show methods on the structured report types.
# See AGENTS.md's "minimal introspection contract" for why reports are
# structured Julia objects in the first place.

@testset "MeshHierarchySnapshot collection interface" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    request_uniform_refinement!(s)
    @test nlevels(s) == 3

    snap = hierarchy_snapshot(s)
    @test snap isa MeshHierarchySnapshot
    @test length(snap) == nlevels(s) == length(snap.levels)
    @test lastindex(snap) == length(snap)

    @test snap[1] === snap.levels[1]
    @test snap[2] === snap.levels[2]
    @test snap[3] === snap.levels[3]
    @test snap[1].level == 1
    @test snap[2].level == 2
    @test snap[3].level == 3

    collected = MeshLevelSnapshot[]
    for lvl in snap
        push!(collected, lvl)
    end
    @test length(collected) == length(snap)
    @test collected == snap.levels

    # iterate protocol directly (mirrors MeshHierarchy/MeshHierarchySession)
    @test collect(snap) == snap.levels
end

@testset "Base.summary one-liners" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)

    r = mesh_report(m)
    q = quality(m)
    nq = Delone.native_quality(m)
    vr = validate(m)
    tr = Delone.tag_report(m)
    gr = generate_mesh(geom; options=MeshOptions(maxh=40.0), result=true)
    mr = Delone.meshability_report(geom; options=MeshOptions(maxh=40.0))
    osr = oodi_snapshot_readiness(m)

    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    refine!(h; mode=:uniform)
    hr = hierarchy_report(h)

    reports = Any[r, q, nq, vr, tr, gr, gr.diagnostics, mr, osr, hr]
    for x in reports
        smry = summary(x)
        @test smry isa String
        @test length(smry) < length(sprint(show, x))
        @test occursin(string(nameof(typeof(x))), smry)
    end

    # Spot-check content, not just length
    @test occursin("min_quality", summary(q))
    @test occursin(string(vr.valid), summary(vr))
    @test occursin(string(hr.nlevels), summary(hr))

    # Deliberately-skipped types (already single terse show lines): confirm
    # they still behave sanely under the generic Base.summary fallback,
    # i.e. we did NOT accidentally break anything by not overriding them.
    lvl_report = level_report(h, 1)
    tref = transfer_report(h, 1, 2)
    rr = refine!(mesh_hierarchy(geom; maxh=40.0, levels=1); mode=:uniform, result=true)
    @test summary(lvl_report) == string(typeof(lvl_report))
    @test summary(tref) == string(typeof(tref))
    @test summary(rr) == string(typeof(rr))
end

@testset "MIME\"text/html\" show methods" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)

    r = mesh_report(m)
    q = quality(m)
    nq = Delone.native_quality(m)
    vr = validate(m)
    tagr = Delone.tag_report(m)
    gr = generate_mesh(geom; options=MeshOptions(maxh=40.0), result=true)
    mr = Delone.meshability_report(geom; options=MeshOptions(maxh=40.0))
    osr = oodi_snapshot_readiness(m)

    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    rres = refine!(h; mode=:uniform, result=true)
    hr = hierarchy_report(h)
    lvl_report = level_report(h, 1)
    tref = transfer_report(h, 1, 2)

    html_of(x) = sprint(show, MIME("text/html"), x)

    for x in Any[r, q, nq, vr, tagr, gr, gr.diagnostics, mr, osr, hr,
                 lvl_report, tref, rres]
        html = html_of(x)
        @test html isa String
        @test occursin("<table", html) || occursin("<pre", html)
        @test !occursin("<html", html)  # snippet, not a full document
    end

    # Spot-check that real field values actually show up.
    @test occursin(string(r.topology.node_count), html_of(r))
    @test occursin(string(round(q.min_quality; digits=4)), html_of(q))
    @test occursin(string(vr.dimension), html_of(vr))
    @test occursin(string(hr.nlevels), html_of(hr))
    @test occursin(string(lvl_report.level), html_of(lvl_report))
    @test occursin(string(tref.coarse_level), html_of(tref))
    @test occursin(string(rres.old_level_count), html_of(rres))

    # Boundary/region tag names are user-controlled (from CAD) — confirm they
    # are escaped rather than skipped when they contain HTML-special chars.
    fake = MeshTagReport(Dict("A<b>&c" => 3), Dict{String,Int}(), 0, 0, DiagnosticMessage[])
    html = html_of(fake)
    @test occursin("A&lt;b&gt;&amp;c", html)
    @test !occursin("A<b>&c", html)

    # Diagnostic messages are also user/backend-controlled text.
    fake_diag = Delone.MeshabilityReport(true, true, 1.0, nothing, "bad <tag> & stuff",
        DiagnosticMessage[])
    html2 = html_of(fake_diag)
    @test occursin("bad &lt;tag&gt; &amp; stuff", html2)
    @test !occursin("bad <tag> & stuff", html2)
end
