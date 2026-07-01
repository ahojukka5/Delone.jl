@testset "BRepCheck_Analyzer (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    a = BRepCheck_Analyzer(box, true)
    @test IsValid(a)

    # Sub-shape validity: each face of the box must be valid
    ex = TopExp_Explorer()
    Init(ex, box, TopAbs_FACE())
    @test IsValid(a, Current(ex))
end

@testset "ShapeFix_Shape (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))
    fixer = ShapeFix_Shape(box)
    SetPrecision(fixer, 1.0e-7)
    SetMinTolerance(fixer, 1.0e-10)
    SetMaxTolerance(fixer, 1.0e-3)
    ok = Perform(fixer)
    @test ok isa Bool
    result = Shape(fixer)
    @test !IsNull(result)
end

@testset "BRep_Tool scalar free functions (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    ex = TopExp_Explorer()

    # Edge tolerance and parameter range
    Init(ex, box, TopAbs_EDGE())
    e = TopoDS_Edge(Current(ex))
    @test BRep_Tool_ToleranceEdge(e) >= 0.0
    t0 = BRep_Tool_FirstParameter(e)
    t1 = BRep_Tool_LastParameter(e)
    @test t0 < t1
    @test isa(BRep_Tool_Degenerated(e), Bool)
    @test isa(BRep_Tool_SameParameter(e), Bool)

    # Face tolerance
    Init(ex, box, TopAbs_FACE())
    f = TopoDS_Face(Current(ex))
    @test BRep_Tool_ToleranceFace(f) >= 0.0

    # Vertex tolerance
    Init(ex, box, TopAbs_VERTEX())
    v = TopoDS_Vertex(Current(ex))
    @test BRep_Tool_ToleranceVertex(v) >= 0.0

    # Closed shape query
    @test isa(BRep_Tool_IsClosed(box), Bool)
end
