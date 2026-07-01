@testset "BRepAdaptor_Curve (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    ex = TopExp_Explorer()
    Init(ex, box, TopAbs_EDGE())
    e = TopoDS_Edge(Current(ex))

    c = BRepAdaptor_Curve(e)
    t0 = FirstParameter(c)
    t1 = LastParameter(c)
    @test t1 > t0

    # Value at both endpoints
    p0 = Value(c, t0)
    p1 = Value(c, t1)
    @test Distance(p0, p1) > 0.0

    # D1: position + tangent vector at start
    p = gp_Pnt(); v = gp_Vec()
    D1(c, t0, p, v)
    @test Magnitude(v) > 0.0

    # D2: position + first + second derivative (second deriv zero on a line)
    p2 = gp_Pnt(); v1 = gp_Vec(); v2 = gp_Vec()
    D2(c, t0, p2, v1, v2)
    @test Magnitude(v1) > 0.0          # tangent must be nonzero
    @test Magnitude(v2) < 1e-10        # line: zero curvature

    @test isa(IsClosed(c), Bool)
    @test isa(IsPeriodic(c), Bool)
    @test Tolerance(c) >= 0.0
end

@testset "BRepAdaptor_Surface (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 2.0, 3.0))

    ex = TopExp_Explorer()
    Init(ex, box, TopAbs_FACE())
    f = TopoDS_Face(Current(ex))

    s = BRepAdaptor_Surface(f)
    u0 = FirstUParameter(s)
    u1 = LastUParameter(s)
    v0 = FirstVParameter(s)
    v1 = LastVParameter(s)
    @test u1 >= u0
    @test v1 >= v0

    um = (u0 + u1) / 2.0
    vm = (v0 + v1) / 2.0

    p = Value(s, um, vm)
    @test isa(p, gp_Pnt)

    # D0: same as Value, in-place
    p2 = gp_Pnt()
    D0(s, um, vm, p2)
    @test Distance(p, p2) < 1e-10

    # D1: partial derivatives
    pd = gp_Pnt(); du = gp_Vec(); dv = gp_Vec()
    D1(s, um, vm, pd, du, dv)
    @test Magnitude(du) + Magnitude(dv) > 0.0

    # Normal: should be a unit vector
    n = Normal(s, um, vm)
    @test isa(n, gp_Dir)

    @test Tolerance(s) >= 0.0
end
