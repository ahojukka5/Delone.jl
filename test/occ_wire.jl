@testset "BRepTools_WireExplorer (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Get a wire from the box
    wex = TopExp_Explorer()
    Init(wex, box, TopAbs_WIRE())
    wire = TopoDS_Wire(Current(wex))

    # Iterate via constructor
    we = BRepTools_WireExplorer(wire)
    edges = TopoDS_Edge[]
    while More(we)
        push!(edges, Current(we))
        Next(we)
    end
    @test length(edges) >= 1

    # Re-initialize via Init(wire)
    we2 = BRepTools_WireExplorer()
    Init(we2, wire)
    @test More(we2)
    e = Current(we2)
    @test !IsNull(e)
    v = CurrentVertex(we2)
    @test !IsNull(v)

    # Init(wire, face) — face helps orient traversal
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))
    # Get the wire of this face
    Init(wex, face, TopAbs_WIRE())
    face_wire = TopoDS_Wire(Current(wex))
    we3 = BRepTools_WireExplorer(face_wire, face)
    @test More(we3)
end

@testset "BRepLProp_SLProps (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    face = TopoDS_Face(Current(fex))

    surf = BRepAdaptor_Surface(face)
    u_mid = 0.5 * (FirstUParameter(surf) + LastUParameter(surf))
    v_mid = 0.5 * (FirstVParameter(surf) + LastVParameter(surf))

    # Constructor (surface, u, v, order, resolution)
    props = BRepLProp_SLProps(surf, u_mid, v_mid, 2, 1.0e-7)
    @test IsNormalDefined(props)
    n = Normal(props)
    @test X(n) isa Float64

    @test IsCurvatureDefined(props)
    # Flat face of box: curvature should be ~ 0
    @test abs(MinCurvature(props)) < 1.0e-6
    @test abs(MaxCurvature(props)) < 1.0e-6
    @test abs(MeanCurvature(props)) < 1.0e-6
    @test abs(GaussianCurvature(props)) < 1.0e-6

    # SetParameters
    SetParameters(props, u_mid + 0.1, v_mid + 0.1)
    @test IsNormalDefined(props)

    # Constructor (surface, order, resolution) — no initial point
    props2 = BRepLProp_SLProps(surf, 2, 1.0e-7)
    SetParameters(props2, u_mid, v_mid)
    @test IsNormalDefined(props2)
end
