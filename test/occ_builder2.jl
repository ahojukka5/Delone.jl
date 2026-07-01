@testset "BRep_Builder (1:1)" begin
    b = BRep_Builder()

    # Build a compound of two boxes
    c = TopoDS_Compound()
    MakeCompound(b, c)
    @test ShapeType(c) == TopAbs_COMPOUND()

    box1 = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    box2 = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))
    Add(b, c, box1)
    Add(b, c, box2)
    @test NbChildren(c) == 2

    Remove(b, c, box1)
    @test NbChildren(c) == 1

    # Build an empty shell
    s = TopoDS_Shell()
    MakeShell(b, s)
    @test ShapeType(s) == TopAbs_SHELL()
end

@testset "gp_GTrsf + BRepBuilderAPI_GTransform (1:1)" begin
    # Identity transform
    t = gp_GTrsf()
    @test Value(t, 1, 1) ≈ 1.0
    @test Value(t, 2, 2) ≈ 1.0
    @test Value(t, 3, 3) ≈ 1.0

    # Non-uniform scaling via SetValue
    SetValue(t, 1, 1, 2.0)  # double along X
    SetValue(t, 3, 3, 3.0)  # triple along Z
    @test Value(t, 1, 1) ≈ 2.0
    @test Value(t, 3, 3) ≈ 3.0

    # IsNegative: identity has positive determinant
    t2 = gp_GTrsf()
    @test !IsNegative(t2)

    # Construct from gp_Trsf (isometry)
    iso = gp_Trsf()
    SetTranslation(iso, gp_Vec(1.0, 0.0, 0.0))
    t3 = gp_GTrsf(iso)
    @test Value(t3, 1, 4) ≈ 1.0  # translation column

    # VectorialPart / SetVectorialPart round-trip
    m = gp_Mat()
    vp = VectorialPart(t)
    @test Value(vp, 1, 1) ≈ 2.0

    # SetTranslationPart / TranslationPart
    xyz = gp_XYZ(5.0, 0.0, 0.0)
    SetTranslationPart(t, xyz)
    tp = TranslationPart(t)
    @test X(tp) ≈ 5.0

    # BRepBuilderAPI_GTransform: apply non-uniform scale to a box
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    scale = gp_GTrsf()
    SetValue(scale, 1, 1, 2.0)
    SetValue(scale, 2, 2, 2.0)
    SetValue(scale, 3, 3, 2.0)
    result = Shape(BRepBuilderAPI_GTransform(box, scale, false))
    @test !IsNull(result)
end

@testset "BRepLProp_CLProps (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))
    ex = TopExp_Explorer()
    Init(ex, box, TopAbs_EDGE())
    edge = TopoDS_Edge(Current(ex))
    curve = BRepAdaptor_Curve(edge)

    t0 = FirstParameter(curve)
    t1 = LastParameter(curve)
    t_mid = 0.5 * (t0 + t1)

    # Constructor (curve, order, resolution), set param later
    props = BRepLProp_CLProps(curve, 2, 1.0e-7)
    SetParameter(props, t_mid)

    @test IsTangentDefined(props)
    td = gp_Dir()
    Tangent(props, td)
    @test X(td)^2 + Y(td)^2 + Z(td)^2 ≈ 1.0 atol=1e-10

    # Position at parameter
    p = Value(props)
    @test X(p) isa Float64

    # Straight edge of box → curvature should be 0
    @test abs(Curvature(props)) < 1.0e-6

    # D1 returns gp_Vec (return value, not out-param)
    dv = D1(props)
    @test Magnitude(dv) > 0.0

    # Constructor (curve, u, order, resolution)
    props2 = BRepLProp_CLProps(curve, t_mid, 2, 1.0e-7)
    @test IsTangentDefined(props2)

    # Constructor (order, resolution) + SetCurve
    props3 = BRepLProp_CLProps(2, 1.0e-7)
    SetCurve(props3, curve)
    SetParameter(props3, t_mid)
    @test IsTangentDefined(props3)
end

@testset "BRepOffsetAPI_MakeOffset (1:1)" begin
    # Create a box face and offset its wire inward
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    wex = TopExp_Explorer()
    Init(wex, face, TopAbs_WIRE())
    wire = TopoDS_Wire(Current(wex))

    m = BRepOffsetAPI_MakeOffset()
    Init(m, face, GeomAbs_Arc(), false)
    AddWire(m, wire)
    Perform(m, -0.05, 0.0)  # negative = inward offset
    @test IsDone(m)
    result = Shape(m)
    @test !IsNull(result)
end

@testset "GeomAbs_JoinType constants" begin
    @test GeomAbs_Arc()          isa Integer
    @test GeomAbs_Tangent()      isa Integer
    @test GeomAbs_Intersection() isa Integer
    # Values are distinct
    vals = [GeomAbs_Arc(), GeomAbs_Tangent(), GeomAbs_Intersection()]
    @test length(unique(vals)) == 3
    # Arc == 0 (OCCT convention)
    @test GeomAbs_Arc() == 0
end
