helper_tet_edges_near(X, T, center, radius) = _edges_near(X, T, center, radius)
helper_tri_edges_near(X, T, center, radius) = _edges_near(X, T, center, radius)

function _edges_near(X, T, center, radius)
    lens = Float64[]
    nv = size(T, 1)
    for e in 1:size(T, 2)
        verts = T[:, e]
        c = sum(X[:, verts[i]] for i in 1:nv) ./ nv
        if sqrt(sum((c .- center) .^ 2)) < radius
            for i in 1:nv, j in (i + 1):nv
                push!(lens, sqrt(sum((X[:, verts[i]] .- X[:, verts[j]]) .^ 2)))
            end
        end
    end
    return lens
end

@testset "LocalSizeField (standalone I.new_localh + SetH/GetH wrapper)" begin
    f = local_size_field((0.0, 0.0, 0.0), (1.0, 1.0, 1.0), 0.3;
        refine_at=[((0.5, 0.5, 0.5), 0.1)])
    @test field_h(f, (0.5, 0.5, 0.5)) <= 0.1 + 1e-10
    @test field_min_h(f, (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)) > 0.0
    restrict_h!(f, (0.2, 0.2, 0.2), 0.05)
    @test field_h(f, (0.2, 0.2, 0.2)) <= 0.05 + 1e-10
    @test_throws ArgumentError local_size_field((0, 0, 0), (1, 1, 1), 0.0)
    @test_throws ArgumentError restrict_h!(f, (0, 0, 0), -1.0)
end

@testset "mesh-level h-field: mesh_h_at / set_global_h! / set_minimal_h!" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test mesh_h_at(m, (0.0, 0.0, 0.0)) > 0.0
    set_global_h!(m, 20.0)
    set_minimal_h!(m, 1.0)
    @test_throws ArgumentError set_global_h!(m, 0.0)
    @test_throws ArgumentError set_minimal_h!(m, -1.0)
end

@testset "restrict_h! / restrict_h_at! (verified: updates GetH, does NOT retroactively steer generate_mesh)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    X = points(m)
    p = Tuple(X[:, size(X, 2) ÷ 2])
    restrict_h!(m, p, 2.0)
    @test mesh_h_at(m, p) <= 2.0 + 1e-9

    far = X[:, argmax([sqrt(sum((X[:, j] .- collect(p)) .^ 2)) for j in 1:size(X, 2)])]
    pts = hcat(collect(p), collect(far))
    m2 = generate_mesh(geom; maxh=40.0)
    restrict_h_at!(m2, pts, [1.0, 3.0])
    @test mesh_h_at(m2, p) <= 1.0 + 1e-9
    @test mesh_h_at(m2, far) <= 3.0 + 1e-9
    @test_throws ArgumentError restrict_h_at!(m2, pts, [1.0])  # shape mismatch

    # Documented limitation: RestrictLocalH on a FRESH mesh before GenerateMesh
    # is discarded by this build's GenerateMesh (it rebuilds its own local-h
    # field during surface meshing). Confirm this explicitly rather than
    # asserting it works.
    m3 = I.new_mesh()
    I.SetGeometry(m3, geom)
    I.RestrictLocalH(m3, I.Point3d(p...), 2.0)
    mp = meshing_parameters(; maxh=40.0)
    I.GenerateMesh(geom, m3, mp)
    m_baseline = generate_mesh(geom; maxh=40.0)
    @test I.GetNE(m3) == I.GetNE(m_baseline)  # restriction had no effect on generation
end

@testset "refine_near! localizes refinement in 3D (apples-to-apples vs unmarked bisect!)" begin
    geom = load_step(STEP)
    m_base = generate_mesh(geom; maxh=40.0)
    X0 = points(m_base)
    target = Tuple(X0[:, size(X0, 2) ÷ 2])
    far_pt = X0[:, argmax([sqrt(sum((X0[:, j] .- collect(target)) .^ 2)) for j in 1:size(X0, 2)])]

    m = copy_mesh(m_base)
    ne0 = num_cells(m)
    refine_near!(m, target; radius=15.0, levels=1)
    @test num_cells(m) > ne0

    X = points(m); T = tetrahedra(m)
    near = helper_tet_edges_near(X, T, collect(target), 8.0)
    far = helper_tet_edges_near(X, T, far_pt, 30.0)
    @test !isempty(near) && !isempty(far)
    # near the refined point, elements are visibly smaller than far away
    @test (sum(near) / length(near)) < (sum(far) / length(far))

    # apples-to-apples: an identical unmarked bisect! pass from the SAME base
    # mesh is measurably coarser near `target` than the marked pass above —
    # this isolates the effect of marking from bisect!'s baseline (mostly
    # uniform) refinement.
    m_unmarked = copy_mesh(m_base)
    mark_for_refinement!(m_unmarked, falses(ne0))
    bisect!(m_unmarked)
    Xu = points(m_unmarked); Tu = tetrahedra(m_unmarked)
    near_unmarked = helper_tet_edges_near(Xu, Tu, collect(target), 8.0)
    @test (sum(near) / length(near)) < (sum(near_unmarked) / length(near_unmarked))

    @test_throws ArgumentError refine_near!(m, target; radius=-1.0)
    @test_throws ArgumentError refine_near!(m, target; radius=1.0, levels=0)
end

@testset "refine_near! on a list of points (single pass covers all)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    X0 = points(m)
    p1 = Tuple(X0[:, size(X0, 2) ÷ 3])
    p2 = Tuple(X0[:, 2 * size(X0, 2) ÷ 3])
    ne0 = num_cells(m)
    refine_near!(m, [p1, p2]; radius=15.0, levels=1)
    @test num_cells(m) > ne0
end

@testset "MeshOptions(local_size=...) declarative front door (3D)" begin
    geom = load_step(STEP)
    m0 = generate_mesh(geom; maxh=40.0)
    X0 = points(m0)
    target = Tuple(X0[:, size(X0, 2) ÷ 2])
    far_pt = X0[:, argmax([sqrt(sum((X0[:, j] .- collect(target)) .^ 2)) for j in 1:size(X0, 2)])]

    opts = mesh_options(; maxh=40.0, local_size=[(target, 5.0, 15.0, 1)])
    res = generate_mesh_result(geom, opts)
    @test res.success
    m = generated_mesh(res)
    X = points(m); T = tetrahedra(m)
    near = helper_tet_edges_near(X, T, collect(target), 8.0)
    far = helper_tet_edges_near(X, T, far_pt, 30.0)
    @test (sum(near) / length(near)) < (sum(far) / length(far))

    # named-tuple entry form
    opts2 = mesh_options(; maxh=40.0,
        local_size=[(point=target, h=5.0, radius=15.0, levels=1)])
    res2 = generate_mesh_result(geom, opts2)
    @test res2.success

    # validation of malformed entries
    @test_throws ArgumentError mesh_options(; maxh=40.0, local_size=[(target, -1.0)])
    @test_throws ArgumentError mesh_options(; maxh=40.0, local_size=[((1.0,), 1.0)])
    @test_throws ArgumentError mesh_options(; maxh=40.0, local_size=[(point=target,)])
end

@testset "plain mark_for_refinement!/bisect! does NOT localize in 2D (raw fact, not what refine_near! uses)" begin
    # This documents a real, still-true fact about the raw bisect! pipeline in
    # 2D -- it is NOT what refine_near!/local_size use in 2D (see the next
    # testset), which dispatches to mark_for_ngx_refinement!/ngx_refine!
    # instead specifically because of this limitation.
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    geo = geometry2d(disk)
    m_base = generate_mesh(geo; maxh=0.15)
    ne0 = num_cells(m_base)
    X0 = points(m_base); T0 = triangles2d(m_base)
    target = [0.0, 0.0, 0.0]

    marked = falses(ne0)
    for e in 1:ne0
        verts = T0[:, e]
        c = sum(X0[:, v] for v in verts) ./ 3
        marked[e] = sqrt(sum((c .- target) .^ 2)) < 0.2
    end
    m_marked = copy_mesh(m_base)
    mark_for_refinement!(m_marked, marked)
    bisect!(m_marked)

    m_unmarked = copy_mesh(m_base)
    mark_for_refinement!(m_unmarked, falses(ne0))
    bisect!(m_unmarked)

    @test num_cells(m_marked) == num_cells(m_unmarked)
    Xm = points(m_marked); Tm = triangles2d(m_marked)
    Xu = points(m_unmarked); Tu = triangles2d(m_unmarked)
    near_marked = helper_tri_edges_near(Xm, Tm, target, 0.1)
    near_unmarked = helper_tri_edges_near(Xu, Tu, target, 0.1)
    @test sum(near_marked) / length(near_marked) ≈ sum(near_unmarked) / length(near_unmarked)
end

@testset "refine_near!/MeshOptions.local_size DOES localize in 2D (via mark_for_ngx_refinement!/ngx_refine!)" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    geo = geometry2d(disk)
    m_base = generate_mesh(geo; maxh=0.3)
    ne0 = num_cells(m_base)
    target = (1.0, 0.0)

    # apples-to-apples control: an UNMARKED ngx_refine! pass leaves the mesh
    # unchanged (unlike bisect!, which always refines uniformly regardless).
    m_unmarked = copy_mesh(m_base)
    mark_for_ngx_refinement!(m_unmarked, falses(ne0))
    ngx_refine!(m_unmarked; reftype=NG_REFINE_H)
    @test num_cells(m_unmarked) == ne0

    # refine_near! near a boundary point grows the mesh...
    m2 = copy_mesh(m_base)
    refine_near!(m2, target; radius=0.3, levels=1)
    @test num_cells(m2) > ne0

    # ...and the growth is genuinely localized: more elements close to the
    # target than close to a point on the opposite side of the disk.
    X2 = points(m2); T2 = triangles2d(m2)
    near_target = length(helper_tri_edges_near(X2, T2, [target..., 0.0], 0.15))
    near_far = length(helper_tri_edges_near(X2, T2, [-target[1], -target[2], 0.0], 0.15))
    @test near_target > near_far

    # geometry-aware: new boundary nodes still land exactly on the true circle.
    S2 = segments2d(m2)
    bnodes = unique(vec(S2))
    radii = [hypot(X2[1, i], X2[2, i]) for i in bnodes]
    @test all(r -> isapprox(r, 1.0; atol=1e-9), radii)

    opts = mesh_options(; maxh=0.3, local_size=[(point=target, h=0.05, radius=0.3)])
    res = generate_mesh_result(geo, opts)
    @test res.success
    @test num_cells(res.mesh) > ne0
end
