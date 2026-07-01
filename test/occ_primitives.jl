@testset "OCC primitives: BRepPrimAPI_* (1:1)" begin
    for (label, shape) in (
        ("box",      Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))),
        ("sphere",   Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 1.0))),
        ("cylinder", Shape(BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(0.0, 0.0, 0.0),
                                                             gp_Dir(0.0, 0.0, 1.0)), 1.0, 2.0))),
    )
        @testset "$label" begin
            @test !IsNull(shape)
            m = generate_mesh(OCCGeometry(shape); maxh=0.6)
            @test Netgen.GetDimension(m) == 3
            @test Netgen.GetNE(m) > 0
        end
    end
end

@testset "OCC sphere refines onto the curved surface (r=1)" begin
    radius(p) = sqrt(p[1]^2 + p[2]^2 + p[3]^2)
    sphere = Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 1.0))
    m = generate_mesh(OCCGeometry(sphere); maxh=0.5)
    bverts() = unique(vec(surface_triangles(m)))
    X = points(m)
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12
    np0 = Netgen.GetNP(m)
    refine!(m)
    X = points(m)
    @test Netgen.GetNP(m) > np0
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12
end
