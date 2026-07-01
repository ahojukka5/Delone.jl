@testset "BRepBuilderAPI_MakeEdge trimmed arcs (1:1)" begin
    ax2 = gp_Ax2(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))
    circ = gp_Circ(ax2, 1.0)

    # Trim by parameter pair
    e1 = Edge(BRepBuilderAPI_MakeEdge(circ, 0.0, pi))
    @test e1 isa TopoDS_Edge
    @test !IsNull(e1)

    # Trim by point pair (points must lie exactly on the circle)
    p1 = gp_Pnt(1.0, 0.0, 0.0)
    p2 = gp_Pnt(-1.0, 0.0, 0.0)
    e2 = Edge(BRepBuilderAPI_MakeEdge(circ, p1, p2))
    @test !IsNull(e2)

    # Trimmed line
    lin = gp_Lin(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(1.0, 0.0, 0.0))
    e3 = Edge(BRepBuilderAPI_MakeEdge(lin, 0.0, 1.0))
    @test !IsNull(e3)
    e4 = Edge(BRepBuilderAPI_MakeEdge(lin, gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 0.0, 0.0)))
    @test !IsNull(e4)

    # gp_Hypr / gp_Parab full + trimmed constructors
    hyp = gp_Hypr(ax2, 1.0, 1.0)
    e5 = Edge(BRepBuilderAPI_MakeEdge(hyp))
    @test !IsNull(e5)
    e6 = Edge(BRepBuilderAPI_MakeEdge(hyp, -1.0, 1.0))
    @test !IsNull(e6)

    parab = gp_Parab(ax2, 1.0)
    e7 = Edge(BRepBuilderAPI_MakeEdge(parab))
    @test !IsNull(e7)
    e8 = Edge(BRepBuilderAPI_MakeEdge(parab, -1.0, 1.0))
    @test !IsNull(e8)
end

@testset "BRepBuilderAPI_MakeWire with mixed line+arc (D-profile) (1:1)" begin
    ax2 = gp_Ax2(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))
    circ = gp_Circ(ax2, 1.0)
    p1 = gp_Pnt(1.0, 0.0, 0.0)
    p2 = gp_Pnt(-1.0, 0.0, 0.0)

    e_line = Edge(BRepBuilderAPI_MakeEdge(p1, p2))
    e_arc  = Edge(BRepBuilderAPI_MakeEdge(circ, p2, p1))

    wb = BRepBuilderAPI_MakeWire()
    Add(wb, e_line)
    Add(wb, e_arc)
    @test IsDone(wb) == true
    @test Error(wb) == BRepBuilderAPI_WireDone()

    w = Wire(wb)
    @test w isa TopoDS_Wire

    @test Edge(wb) isa TopoDS_Edge
    @test Vertex(wb) isa TopoDS_Vertex

    # Make a face from the D-profile wire
    mf = BRepBuilderAPI_MakeFace(w, true)
    f = Face(mf)
    @test !IsNull(f)

    # An empty wire builder reports EmptyWire and is not done
    wb_empty = BRepBuilderAPI_MakeWire()
    @test IsDone(wb_empty) == false
    @test Error(wb_empty) == BRepBuilderAPI_EmptyWire()

    # Add via TopTools_ListOfShape
    l = TopTools_ListOfShape()
    Append(l, e_line)
    Append(l, e_arc)
    wb2 = BRepBuilderAPI_MakeWire()
    Add(wb2, l)
    @test IsDone(wb2) == true
end

@testset "BRepBuilderAPI_MakeFace analytic surfaces (1:1)" begin
    ax3 = gp_Ax3(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))

    cyl = gp_Cylinder(ax3, 1.0)
    f1 = Face(BRepBuilderAPI_MakeFace(cyl))
    @test !IsNull(f1)
    f2 = Face(BRepBuilderAPI_MakeFace(cyl, 0.0, pi, 0.0, 2.0))
    @test !IsNull(f2)

    cone = gp_Cone(ax3, 0.3, 1.0)
    f3 = Face(BRepBuilderAPI_MakeFace(cone))
    @test !IsNull(f3)
    f4 = Face(BRepBuilderAPI_MakeFace(cone, 0.0, pi, 0.0, 2.0))
    @test !IsNull(f4)

    sph = gp_Sphere(ax3, 1.0)
    f5 = Face(BRepBuilderAPI_MakeFace(sph))
    @test !IsNull(f5)
    f6 = Face(BRepBuilderAPI_MakeFace(sph, 0.0, pi, -pi/2, pi/2))
    @test !IsNull(f6)

    tor = gp_Torus(ax3, 2.0, 0.5)
    f7 = Face(BRepBuilderAPI_MakeFace(tor))
    @test !IsNull(f7)
    f8 = Face(BRepBuilderAPI_MakeFace(tor, 0.0, pi, 0.0, 2pi))
    @test !IsNull(f8)

    pln = gp_Pln(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))
    f9 = Face(BRepBuilderAPI_MakeFace(pln, -1.0, 1.0, -1.0, 1.0))
    @test !IsNull(f9)
end

@testset "BRepBuilderAPI_MakeSolid multi-shell constructors (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    sphere = Shape(BRepPrimAPI_MakeSphere(1.0))

    bex = TopExp_Explorer(); Init(bex, box, TopAbs_SHELL())
    shell1 = TopoDS_Shell(Current(bex))

    spex = TopExp_Explorer(); Init(spex, sphere, TopAbs_SHELL())
    shell2 = TopoDS_Shell(Current(spex))

    ms1 = BRepBuilderAPI_MakeSolid(shell1)
    @test IsDone(ms1) == true
    solid1 = Solid(ms1)
    @test !IsNull(solid1)

    ms2 = BRepBuilderAPI_MakeSolid(shell1, shell2)
    @test ms2 isa BRepBuilderAPI_MakeSolid

    ms3 = BRepBuilderAPI_MakeSolid(shell1, shell2, shell1)
    @test ms3 isa BRepBuilderAPI_MakeSolid

    ms4 = BRepBuilderAPI_MakeSolid(solid1)
    @test ms4 isa BRepBuilderAPI_MakeSolid

    ms5 = BRepBuilderAPI_MakeSolid(solid1, shell1)
    @test ms5 isa BRepBuilderAPI_MakeSolid

    @test IsDeleted(ms1, box) isa Bool
end
