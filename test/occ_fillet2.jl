@testset "BRepFilletAPI_MakeFillet extended control (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    eex = TopExp_Explorer()
    Init(eex, box, TopAbs_EDGE())
    e1 = TopoDS_Edge(Current(eex)); Next(eex)
    e2 = TopoDS_Edge(Current(eex))

    # Single constant-radius fillet -- query/edit the contour BEFORE Build()
    # (BRepFilletAPI_MakeFillet finalizes its internal spine data in Build(),
    # so SetRadius/Radius/IsConstant must run on the pre-Build state).
    mf1 = BRepFilletAPI_MakeFillet(box)
    Add(mf1, 0.1, e1)
    @test NbContours(mf1) == 1
    @test IsConstant(mf1, 1) == true
    @test Radius(mf1, 1) ≈ 0.1
    @test Edge(mf1, 1, 1) isa TopoDS_Edge

    # SetRadius updates the contour radius
    SetRadius(mf1, 0.2, 1, 1)
    @test Radius(mf1, 1) ≈ 0.2

    Build(mf1)
    @test IsDone(mf1) == true
    @test !IsNull(Shape(mf1))

    # Two-radius (linear evolution) fillet is not constant
    mf2 = BRepFilletAPI_MakeFillet(box)
    Add(mf2, 0.1, 0.2, e2)
    @test IsConstant(mf2, 1) == false
    Build(mf2)
    @test IsDone(mf2) == true
end

@testset "BRepFilletAPI_MakeChamfer extended control (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    eex = TopExp_Explorer()
    Init(eex, face, TopAbs_EDGE())
    edge_on_face = TopoDS_Edge(Current(eex))

    # Asymmetric two-distance chamfer
    mc1 = BRepFilletAPI_MakeChamfer(box)
    Add(mc1, 0.1, 0.2, edge_on_face, face)
    Build(mc1)
    @test IsDone(mc1) == true
    @test !IsNull(Shape(mc1))

    # Distance-angle chamfer
    box2 = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    fex2 = TopExp_Explorer(); Init(fex2, box2, TopAbs_FACE())
    face2 = TopoDS_Face(Current(fex2))
    eex2 = TopExp_Explorer(); Init(eex2, face2, TopAbs_EDGE())
    edge2 = TopoDS_Edge(Current(eex2))

    mc2 = BRepFilletAPI_MakeChamfer(box2)
    AddDA(mc2, 0.1, pi/6, edge2, face2)
    Build(mc2)
    @test IsDone(mc2) == true
    @test !IsNull(Shape(mc2))
end
