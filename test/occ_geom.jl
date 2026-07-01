@testset "Geom_Curve construction and evaluation (1:1)" begin
    # Clamped linear B-spline through 3 points: sum(mults) = nPoles + degree + 1 = 5
    poles = Float64[0.0,0.0,0.0, 1.0,0.0,0.0, 2.0,0.0,0.0]
    knots = Float64[0.0, 0.5, 1.0]
    mults = Int32[2, 1, 2]
    c = Geom_BSplineCurve(poles, knots, mults, 1, false)

    @test FirstParameter(c) ≈ 0.0
    @test LastParameter(c) ≈ 1.0
    @test IsClosed(c) == false
    @test IsPeriodic(c) == false
    @test Continuity(c) isa Integer

    p0 = Value(c, 0.0)
    p1 = Value(c, 1.0)
    @test X(p0) ≈ 0.0 && Y(p0) ≈ 0.0 && Z(p0) ≈ 0.0
    @test X(p1) ≈ 2.0 && Y(p1) ≈ 0.0 && Z(p1) ≈ 0.0

    tangent = D1(c, 0.5)
    @test tangent isa gp_Vec

    rc = Reversed(c)
    @test FirstParameter(rc) isa Float64

    # Turn the new curve into a real TopoDS_Edge
    e = Edge(BRepBuilderAPI_MakeEdge(c))
    @test !IsNull(e)
    e_trimmed_param = Edge(BRepBuilderAPI_MakeEdge(c, 0.0, 0.5))
    @test !IsNull(e_trimmed_param)
    e_trimmed_pts = Edge(BRepBuilderAPI_MakeEdge(c, gp_Pnt(0.0,0.0,0.0), gp_Pnt(1.0,0.0,0.0)))
    @test !IsNull(e_trimmed_pts)
end

@testset "Geom_BezierCurve construction (1:1)" begin
    poles = Float64[0.0,0.0,0.0, 1.0,2.0,0.0, 2.0,0.0,0.0]
    bez = Geom_BezierCurve(poles)
    p0 = Value(bez, FirstParameter(bez))
    @test X(p0) ≈ 0.0 && Y(p0) ≈ 0.0

    weights = Float64[1.0, 1.0, 1.0]
    rbez = Geom_BezierCurve(poles, weights)
    @test FirstParameter(rbez) isa Float64
end

@testset "BRep_Tool_Curve / BRep_Tool_Surface bridge (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    eex = TopExp_Explorer()
    Init(eex, box, TopAbs_EDGE())
    edge0 = TopoDS_Edge(Current(eex))

    curve0 = BRep_Tool_Curve(edge0)
    # The underlying curve's own domain need not match the edge's trim window
    # (e.g. a box edge sits on an infinite Geom_Line) -- just confirm it evaluates.
    mid = (FirstParameter(curve0) + LastParameter(curve0)) / 2
    @test Value(curve0, mid) isa gp_Pnt

    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face0 = TopoDS_Face(Current(fex))

    surf0 = BRep_Tool_Surface(face0)
    @test Value(surf0, 0.5, 0.5) isa gp_Pnt
    # Box faces are untrimmed infinite Geom_Plane surfaces.
    @test IsUClosed(surf0) == false
    @test IsVClosed(surf0) == false
    @test IsUPeriodic(surf0) == false
    @test IsVPeriodic(surf0) == false
    @test Continuity(surf0) isa Integer
end

@testset "BRepBuilderAPI_MakeFace from Handle(Geom_Surface) (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))

    # Robustly find the top face (z = 2.0) by centroid, not explorer order.
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    topface = nothing
    while More(fex)
        f = TopoDS_Face(Current(fex))
        g = GProp_GProps()
        BRepGProp_SurfaceProperties(f, g)
        cm = CentreOfMass(g)
        if isapprox(Z(cm), 2.0; atol=1.0e-9)
            topface = f
            break
        end
        Next(fex)
    end
    @test topface !== nothing

    surf = BRep_Tool_Surface(topface)

    poly = BRepBuilderAPI_MakePolygon()
    Add(poly, gp_Pnt(0.5, 0.5, 2.0)); Add(poly, gp_Pnt(1.5, 0.5, 2.0))
    Add(poly, gp_Pnt(1.5, 1.5, 2.0)); Add(poly, gp_Pnt(0.5, 1.5, 2.0))
    Close(poly)
    w = Wire(poly)

    f2 = Face(BRepBuilderAPI_MakeFace(surf, w, true))
    @test !IsNull(f2)

    f3 = Face(BRepBuilderAPI_MakeFace(surf, 0.0, 1.0, 0.0, 1.0, 1.0e-7))
    @test !IsNull(f3)

    f4 = Face(BRepBuilderAPI_MakeFace(surf, 1.0e-7))
    @test !IsNull(f4)
end

@testset "GeomAPI_PointsToBSpline (1:1)" begin
    points = Float64[0.0,0.0,0.0, 1.0,1.0,0.0, 2.0,0.0,0.0, 3.0,1.0,0.0]
    fit = GeomAPI_PointsToBSpline(points, 3, 8, GeomAbs_C2(), 1.0e-3)

    pfirst = Value(fit, FirstParameter(fit))
    plast  = Value(fit, LastParameter(fit))
    @test X(pfirst) ≈ 0.0 atol=1.0e-6
    @test Y(pfirst) ≈ 0.0 atol=1.0e-6
    @test X(plast) ≈ 3.0 atol=1.0e-6
    @test Y(plast) ≈ 1.0 atol=1.0e-6
end

@testset "GeomAPI_ProjectPointOnCurve (1:1)" begin
    c = Geom_BSplineCurve(Float64[0.0,0.0,0.0, 1.0,0.0,0.0, 2.0,0.0,0.0],
                          Float64[0.0,0.5,1.0], Int32[2,1,2], 1, false)
    proj = GeomAPI_ProjectPointOnCurve(gp_Pnt(1.0, 5.0, 0.0), c)
    @test NbPoints(proj) >= 1
    np = NearestPoint(proj)
    @test X(np) ≈ 1.0 atol=1.0e-6
    @test Y(np) ≈ 0.0 atol=1.0e-6
    @test LowerDistance(proj) ≈ 5.0 atol=1.0e-6
    @test LowerDistanceParameter(proj) isa Float64
    @test Point(proj, 1) isa gp_Pnt
    @test Distance(proj, 1) isa Float64

    # Range-bounded constructor overload
    proj2 = GeomAPI_ProjectPointOnCurve(gp_Pnt(1.0, 5.0, 0.0), c, 0.0, 1.0)
    @test NbPoints(proj2) >= 1
end

@testset "GeomAPI_ProjectPointOnSurf (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face0 = TopoDS_Face(Current(fex))
    surf0 = BRep_Tool_Surface(face0)

    projs = GeomAPI_ProjectPointOnSurf(gp_Pnt(0.5, 0.5, 5.0), surf0)
    @test IsDone(projs) == true
    @test NbPoints(projs) >= 1
    @test NearestPoint(projs) isa gp_Pnt
    @test LowerDistance(projs) >= 0.0
    @test Point(projs, 1) isa gp_Pnt
    @test Distance(projs, 1) isa Float64
end

@testset "GeomAPI_ExtremaCurveCurve (1:1)" begin
    c1 = Geom_BSplineCurve(Float64[0.0,0.0,0.0, 1.0,0.0,0.0, 2.0,0.0,0.0],
                           Float64[0.0,0.5,1.0], Int32[2,1,2], 1, false)
    c2 = Geom_BSplineCurve(Float64[0.0,1.0,0.0, 1.0,1.0,0.0, 2.0,1.0,0.0],
                           Float64[0.0,0.5,1.0], Int32[2,1,2], 1, false)
    ext = GeomAPI_ExtremaCurveCurve(c1, c2)
    @test NbExtrema(ext) >= 1
    @test IsParallel(ext) == true
    @test LowerDistance(ext) ≈ 1.0 atol=1.0e-6
    @test TotalLowerDistance(ext) >= 0.0
    @test Distance(ext, 1) isa Float64
end
