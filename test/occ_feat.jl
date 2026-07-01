@testset "BRepFeat_MakePrism boss on a box (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))

    # Find the top face (z = 2.0) by its centroid, robust to TopExp_Explorer ordering.
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    topface = nothing
    while More(fex)
        f = TopoDS_Face(Current(fex))
        g = GProp_GProps()
        BRepGProp_SurfaceProperties(f, g)
        c = CentreOfMass(g)
        if isapprox(Z(c), 2.0; atol=1.0e-9)
            topface = f
            break
        end
        Next(fex)
    end
    @test topface !== nothing

    # A circular profile face coplanar with the top face (the boss footprint).
    ax2 = gp_Ax2(gp_Pnt(1.0, 1.0, 2.0), gp_Dir(0.0, 0.0, 1.0))
    circ = gp_Circ(ax2, 0.5)
    edge = Edge(BRepBuilderAPI_MakeEdge(circ))
    wire = Wire(BRepBuilderAPI_MakeWire(edge))
    pbase = Face(BRepBuilderAPI_MakeFace(wire, true))

    dir = gp_Dir(0.0, 0.0, 1.0)
    mp = BRepFeat_MakePrism(box, pbase, topface, dir, 1, true)  # Fuse=1 -> add material (boss)
    Perform(mp, 1.0)
    @test IsDone(mp) == true
    result = Shape(mp)
    @test !IsNull(result)

    # Default constructor + Init + Add round-trip shouldn't throw
    mp2 = BRepFeat_MakePrism()
    Init(mp2, box, pbase, topface, dir, 1, true)
    @test mp2 isa BRepFeat_MakePrism
    @test_nowarn PerformUntilEnd(mp2)
end

@testset "BRepFeat_MakeRevol API surface (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))

    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    topface = nothing
    while More(fex)
        f = TopoDS_Face(Current(fex))
        g = GProp_GProps()
        BRepGProp_SurfaceProperties(f, g)
        c = CentreOfMass(g)
        if isapprox(Z(c), 2.0; atol=1.0e-9)
            topface = f
            break
        end
        Next(fex)
    end
    @test topface !== nothing

    ax2 = gp_Ax2(gp_Pnt(1.0, 1.0, 2.0), gp_Dir(0.0, 0.0, 1.0))
    circ = gp_Circ(ax2, 0.5)
    edge = Edge(BRepBuilderAPI_MakeEdge(circ))
    wire = Wire(BRepBuilderAPI_MakeWire(edge))
    pbase = Face(BRepBuilderAPI_MakeFace(wire, true))

    axis = gp_Ax1(gp_Pnt(1.0, 1.0, 2.0), gp_Dir(1.0, 0.0, 0.0))
    mr = BRepFeat_MakeRevol(box, pbase, topface, axis, 1, true)
    @test mr isa BRepFeat_MakeRevol

    mr2 = BRepFeat_MakeRevol()
    Init(mr2, box, pbase, topface, axis, 1, true)
    @test mr2 isa BRepFeat_MakeRevol
end
