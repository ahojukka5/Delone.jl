@testset "OCC kernel (raw 1:1): primitives, booleans, traversal, IO" begin
    # Build shapes from raw OCCT classes, then mesh via OCCGeometry.
    box = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))
    @test !IsNull(box)
    @test ShapeType(box) == 2                         # TopAbs_SOLID
    for shape in (box,
                  Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 1.0)),
                  Shape(BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(0.0, 0.0, 0.0),
                                                        gp_Dir(0.0, 0.0, 1.0)), 1.0, 2.0)))
        m = generate_mesh(OCCGeometry(shape); maxh=0.6)
        @test Netgen.GetDimension(m) == 3
        @test Netgen.GetNE(m) > 0
    end

    # TopExp_Explorer sub-shape traversal (TopAbs_FACE = 4)
    function nfaces(shape)
        ex = TopExp_Explorer(); Init(ex, shape, 4)
        n = 0; while More(ex); n += 1; Next(ex); end
        return n
    end
    @test nfaces(box) == 6
    @test nfaces(Shape(BRepPrimAPI_MakeCylinder(1.0, 2.0))) == 3

    # Boolean: box minus sphere
    cut = Shape(BRepAlgoAPI_Cut(box, Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 0.6))))
    @test Netgen.GetNE(generate_mesh(OCCGeometry(cut); maxh=0.3)) > 0

    # BREP write/read round-trip via raw BRepTools
    f = tempname() * ".brep"
    @test BRepTools_Write(box, f)
    s2 = TopoDS_Shape(); @test BRepTools_Read(s2, f)
    @test nfaces(s2) == 6
    rm(f; force=true)
end

@testset "OCC sphere refines onto the curved surface (r=1)" begin
    radius(p) = sqrt(p[1]^2 + p[2]^2 + p[3]^2)
    sphere = Shape(BRepPrimAPI_MakeSphere(gp_Pnt(0.0, 0.0, 0.0), 1.0))
    m = generate_mesh(OCCGeometry(sphere); maxh=0.5)
    bverts() = unique(vec(surface_triangles(m)))
    X = points(m)
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12   # coarse on sphere
    np0 = Netgen.GetNP(m)
    refine!(m)
    X = points(m)
    @test Netgen.GetNP(m) > np0
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12   # still on sphere
end
