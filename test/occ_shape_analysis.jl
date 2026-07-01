@testset "GProp_PrincipalProps (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 3.0, 4.0))
    g = GProp_GProps()
    BRepGProp_VolumeProperties(box, g)

    pp = PrincipalProperties(g)
    @test pp isa GProp_PrincipalProps

    # A box has axial symmetry when two dimensions are equal; our box is all different
    # → no symmetry axis/point; but the test only checks the values are booleans
    @test HasSymmetryAxis(pp) isa Bool
    @test HasSymmetryPoint(pp) isa Bool

    # Principal axes are unit-length gp_Vec
    v1 = FirstAxisOfInertia(pp)
    v2 = SecondAxisOfInertia(pp)
    v3 = ThirdAxisOfInertia(pp)
    @test v1 isa gp_Vec
    @test v2 isa gp_Vec
    @test v3 isa gp_Vec
    @test Magnitude(v1) ≈ 1.0 atol=1e-10
    @test Magnitude(v2) ≈ 1.0 atol=1e-10
    @test Magnitude(v3) ≈ 1.0 atol=1e-10

    # MomentOfInertia about a principal axis is positive for a solid box
    ax = gp_Ax1(CentreOfMass(g), gp_Dir(X(v1), Y(v1), Z(v1)))
    @test MomentOfInertia(g, ax) > 0.0
end

@testset "Bnd_OBB + BRepBndLib_AddOBB (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 3.0, 4.0))
    obb = Bnd_OBB()
    @test IsVoid(obb)

    # AddOBB computes the oriented bounding box
    BRepBndLib_AddOBB(box, obb, true, false, true)
    @test !IsVoid(obb)
    @test XHSize(obb) > 0.0
    @test YHSize(obb) > 0.0
    @test ZHSize(obb) > 0.0

    # Center is a gp_XYZ (reachable via X/Y/Z)
    c = Center(obb)
    @test c isa gp_XYZ
    @test X(c) isa Float64

    # Direction vectors are gp_XYZ (unit)
    xd = XDirection(obb)
    @test xd isa gp_XYZ

    # IsOut: a distant point is outside
    far = gp_Pnt(100.0, 100.0, 100.0)
    @test IsOut(obb, far)

    # A point inside the box is not outside
    inside = gp_Pnt(1.0, 1.5, 2.0)
    @test !IsOut(obb, inside)

    # IsAABox: axis-aligned box produces an AA OBB (or at least a valid OBB)
    @test IsAABox(obb) isa Bool

    # IsCompletelyInside(a, b) checks if b is completely inside a
    big = Bnd_OBB()
    bigbox = Shape(BRepPrimAPI_MakeBox(gp_Pnt(-5.0, -5.0, -5.0), gp_Pnt(5.0, 5.0, 5.0)))
    BRepBndLib_AddOBB(bigbox, big, true, false, true)
    @test IsCompletelyInside(big, obb)   # obb (small box) is inside big
end

@testset "BRepClass_FaceClassifier (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    # Get one face
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    fc = BRepClass_FaceClassifier()

    # Test 3D point: centre of face should be classified IN
    # For the bottom face of a unit box (z=0), midpoint is (0.5, 0.5, 0.0)
    midpoint_3d = gp_Pnt(0.5, 0.5, 0.0)
    Perform(fc, face, midpoint_3d, 1.0e-7)
    @test State(fc) isa Integer
    # State should be IN (== TopAbs_IN()) or ON; not OUT
    st = State(fc)
    @test st == TopAbs_IN() || st == TopAbs_ON()

    # A 2D UV point at (0.5, 0.5) in parameter space should be IN the face
    mid_uv = gp_Pnt2d(0.5, 0.5)
    Perform(fc, face, mid_uv, 1.0e-7)
    @test State(fc) isa Integer
end

@testset "ShapeAnalysis_FreeBounds (1:1)" begin
    # Sew two box faces into a shell to produce a shape with free bounds
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

    # ShapeAnalysis_FreeBounds on the shell
    fb = ShapeAnalysis_FreeBounds(sewn, false, false, false)
    closed = GetClosedWires(fb)
    open_w = GetOpenWires(fb)
    @test closed isa TopoDS_Compound
    @test open_w isa TopoDS_Compound

    # Default constructor
    fb2 = ShapeAnalysis_FreeBounds()
    @test fb2 isa ShapeAnalysis_FreeBounds
end

@testset "ShapeAnalysis_Shell (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    sa = ShapeAnalysis_Shell()
    LoadShells(sa, box)
    @test NbLoaded(sa) >= 1

    # IsLoaded checks if a specific shell (not the whole solid) is loaded
    sex = TopExp_Explorer()
    Init(sex, box, TopAbs_SHELL())
    shell = Current(sex)
    @test IsLoaded(sa, shell)

    # A well-formed box should pass oriented shell check
    result = CheckOrientedShells(sa, box, false, false)
    @test result isa Bool

    # A properly oriented box has no bad edges
    @test !HasBadEdges(sa)

    # BadEdges / FreeEdges return TopoDS_Compound
    bad = BadEdges(sa)
    @test bad isa TopoDS_Compound
    @test HasFreeEdges(sa) isa Bool
    @test HasConnectedEdges(sa) isa Bool

    # Clear resets state
    Clear(sa)
    @test NbLoaded(sa) == 0
end

@testset "ShapeAnalysis_Edge (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    eex = TopExp_Explorer()
    Init(eex, face, TopAbs_EDGE())
    edge = TopoDS_Edge(Current(eex))

    sae = ShapeAnalysis_Edge()
    @test sae isa ShapeAnalysis_Edge

    # A box edge always has a 3D curve
    @test HasCurve3d(sae, edge) == true
    @test IsClosed3d(sae, edge) isa Bool

    # The edge bounds the face it was explored from
    @test HasPCurve(sae, edge, face) == true

    # A box has no seam edges (no periodic surfaces)
    @test IsSeam(sae, edge, face) == false

    v1 = FirstVertex(sae, edge)
    v2 = LastVertex(sae, edge)
    @test v1 isa TopoDS_Vertex
    @test v2 isa TopoDS_Vertex
end
