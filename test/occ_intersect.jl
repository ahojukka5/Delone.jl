@testset "IntCurvesFace_ShapeIntersector (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Ray along X through the centre of the box (y=0.5, z=0.5)
    origin = gp_Pnt(-1.0, 0.5, 0.5)
    ray = gp_Lin(origin, gp_Dir(1.0, 0.0, 0.0))

    s = IntCurvesFace_ShapeIntersector()
    Load(s, box, 1.0e-7)
    Perform(s, ray, -1e10, 1e10)

    @test IsDone(s)
    @test NbPnt(s) >= 2

    # Sort by W parameter (distance along ray) and check ordering
    SortResult(s)
    n = NbPnt(s)
    for i in 1:(n-1)
        @test WParameter(s, i) <= WParameter(s, i+1)
    end

    # First and last intersection points should be on the box surface
    p1 = Pnt(s, 1)
    @test X(p1) isa Float64
    f1 = Face(s, 1)
    @test !IsNull(f1)

    # UV parameters are real numbers
    @test UParameter(s, 1) isa Float64
    @test VParameter(s, 1) isa Float64

    # State returns an integer (TopAbs_State)
    @test State(s, 1) isa Integer

    # Transition constants are distinct integers
    @test IntCurveSurface_Tangent() isa Integer
    @test IntCurveSurface_In()      isa Integer
    @test IntCurveSurface_Out()     isa Integer
    vals = [IntCurveSurface_Tangent(), IntCurveSurface_In(), IntCurveSurface_Out()]
    @test length(unique(vals)) == 3
end

@testset "IntCurvesFace_ShapeIntersector PerformNearest (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    origin = gp_Pnt(-2.0, 0.5, 0.5)
    ray = gp_Lin(origin, gp_Dir(1.0, 0.0, 0.0))

    s = IntCurvesFace_ShapeIntersector()
    Load(s, box, 1.0e-7)
    PerformNearest(s, ray, -1e10, 1e10)

    @test IsDone(s)
    # PerformNearest returns at most 1 result
    @test NbPnt(s) <= 1
end
