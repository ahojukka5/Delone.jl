@testset "BRepBuilderAPI_Sewing (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Sew a closed box — all edges already contiguous, so NbFreeEdges == 0
    sewer = BRepBuilderAPI_Sewing(1.0e-6)
    Add(sewer, box)
    Perform(sewer)
    result = SewedShape(sewer)
    @test !IsNull(result)
    @test NbFreeEdges(sewer) == 0
    @test NbMultipleEdges(sewer) == 0

    # SetTolerance / Tolerance round-trip
    sewer2 = BRepBuilderAPI_Sewing()
    SetTolerance(sewer2, 1.0e-5)
    @test Tolerance(sewer2) ≈ 1.0e-5

    # NbContigousEdges is available
    @test NbContigousEdges(sewer) isa Integer
end

@testset "BRepClass3d_SolidClassifier (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Constructor (shape)
    clf = BRepClass3d_SolidClassifier(box)

    # Interior point → TopAbs_IN
    interior = gp_Pnt(0.5, 0.5, 0.5)
    Perform(clf, interior, 1.0e-7)
    @test State(clf) == TopAbs_IN()

    # Exterior point → TopAbs_OUT
    exterior = gp_Pnt(2.0, 2.0, 2.0)
    Perform(clf, exterior, 1.0e-7)
    @test State(clf) == TopAbs_OUT()

    # Load from default constructor
    clf2 = BRepClass3d_SolidClassifier()
    Load(clf2, box)
    Perform(clf2, interior, 1.0e-7)
    @test State(clf2) == TopAbs_IN()

    # IsOnAFace
    @test isa(IsOnAFace(clf2), Bool)

    # PerformInfinitePoint — checks solid orientation
    PerformInfinitePoint(clf, 1.0e-7)
    @test isa(State(clf), Integer)
end

@testset "TopAbs_IN/OUT/ON/UNKNOWN constants" begin
    @test TopAbs_IN()      isa Integer
    @test TopAbs_OUT()     isa Integer
    @test TopAbs_ON()      isa Integer
    @test TopAbs_UNKNOWN() isa Integer
    # State values are distinct
    states = [TopAbs_IN(), TopAbs_OUT(), TopAbs_ON(), TopAbs_UNKNOWN()]
    @test length(unique(states)) == 4
end
