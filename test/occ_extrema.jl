@testset "BRepExtrema_DistShapeShape (1:1)" begin
    # Two non-touching boxes
    box1 = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    t = gp_Trsf()
    SetTranslation(t, gp_Vec(3.0, 0.0, 0.0))
    box2 = Shape(BRepBuilderAPI_Transform(box1, t, false))

    d = BRepExtrema_DistShapeShape(box1, box2)
    @test IsDone(d)
    @test Value(d) ≈ 2.0 atol=1e-10
    @test NbSolution(d) >= 1
    p1 = PointOnShape1(d, 1)
    p2 = PointOnShape2(d, 1)
    @test X(p1) isa Float64
    @test X(p2) isa Float64
    @test !InnerSolution(d)

    # Two overlapping boxes → distance == 0, InnerSolution
    box3 = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.5, 0.5, 0.5), gp_Pnt(1.5, 1.5, 1.5)))
    d2 = BRepExtrema_DistShapeShape(box1, box3)
    @test IsDone(d2)
    @test InnerSolution(d2)
    @test Value(d2) ≈ 0.0 atol=1e-10

    # Perform() re-computation
    d3 = BRepExtrema_DistShapeShape()
    # Default-constructed then not performed — IsDone should be false
    @test !IsDone(d3)
end

@testset "ShapeAnalysis_ShapeContents (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    c = ShapeAnalysis_ShapeContents()
    Perform(c, box)
    @test NbFaces(c) == 6
    @test NbEdges(c) == 24    # counts with multiplicity: 12 unique edges × 2 face refs each
    @test NbVertices(c) == 48 # counts with multiplicity: 8 unique × traversal depth
    @test NbShells(c) >= 1
    @test NbSolids(c) >= 1
    @test NbWires(c) >= 1
end

@testset "TopExp_FirstVertex / TopExp_LastVertex (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    ex = TopExp_Explorer()
    Init(ex, box, TopAbs_EDGE())
    edge = TopoDS_Edge(Current(ex))

    v1 = TopExp_FirstVertex(edge, true)
    v2 = TopExp_LastVertex(edge, true)
    @test !IsNull(v1)
    @test !IsNull(v2)

    # Vertices should be distinct (edge has two endpoints)
    @test !IsSame(v1, v2)

    # Without orientation flag
    v3 = TopExp_FirstVertex(edge, false)
    @test !IsNull(v3)
end
