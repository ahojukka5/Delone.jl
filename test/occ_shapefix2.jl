@testset "ShapeFix_FreeBounds (1:1)" begin
    # Sew two box faces into a shell with free (open) boundaries
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    f1 = TopoDS_Face(Current(fex)); Next(fex)
    f2 = TopoDS_Face(Current(fex))

    sewer = BRepBuilderAPI_Sewing()
    Add(sewer, f1)
    Add(sewer, f2)
    Perform(sewer)
    sewn = SewedShape(sewer)

    fb = ShapeFix_FreeBounds(sewn, 1.0e-6, 1.0e-6, false, false)
    @test fb isa ShapeFix_FreeBounds
    @test GetClosedWires(fb) isa TopoDS_Compound
    @test GetOpenWires(fb) isa TopoDS_Compound
    @test GetShape(fb) isa TopoDS_Shape

    # 4-arg constructor variant
    fb2 = ShapeFix_FreeBounds(sewn, 1.0e-6, false, false)
    @test fb2 isa ShapeFix_FreeBounds

    # Default constructor
    fb3 = ShapeFix_FreeBounds()
    @test fb3 isa ShapeFix_FreeBounds
end

@testset "ShapeFix_ShapeTolerance (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    st = ShapeFix_ShapeTolerance()
    @test st isa ShapeFix_ShapeTolerance

    @test_nowarn SetTolerance(st, box, 0.01, TopAbs_FACE())
    @test LimitTolerance(st, box, 0.001, 0.01, TopAbs_FACE()) isa Bool
end

@testset "ShapeFix_Wireframe (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    wf = ShapeFix_Wireframe(box)
    @test wf isa ShapeFix_Wireframe
    @test FixWireGaps(wf) isa Bool
    @test FixSmallEdges(wf) isa Bool
    @test Shape(wf) isa TopoDS_Shape

    SetLimitAngle(wf, 0.1)
    @test LimitAngle(wf) ≈ 0.1

    # Default constructor + explicit Load
    wf2 = ShapeFix_Wireframe()
    @test wf2 isa ShapeFix_Wireframe
    @test_nowarn Load(wf2, box)
end

@testset "ShapeUpgrade_UnifySameDomain (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    u = ShapeUpgrade_UnifySameDomain(box, true, true, false)
    @test u isa ShapeUpgrade_UnifySameDomain
    Build(u)
    result = Shape(u)
    @test result isa TopoDS_Shape
    @test !IsNull(result)

    # Default constructor + Initialize
    u2 = ShapeUpgrade_UnifySameDomain()
    @test u2 isa ShapeUpgrade_UnifySameDomain
    Initialize(u2, box, true, true, false)
    @test_nowarn AllowInternalEdges(u2, false)
    @test_nowarn SetSafeInputMode(u2, true)
    @test_nowarn SetLinearTolerance(u2, 1.0e-6)
    @test_nowarn SetAngularTolerance(u2, 1.0e-6)
    @test_nowarn KeepShape(u2, box)
    Build(u2)
    @test Shape(u2) isa TopoDS_Shape
end
