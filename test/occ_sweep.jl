@testset "BRepOffsetAPI_ThruSections (loft, 1:1)" begin
    # Two concentric circles at z=0 and z=2 lofted into a cylinder shell
    ax1 = gp_Ax2(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))
    ax2 = gp_Ax2(gp_Pnt(0.0, 0.0, 2.0), gp_Dir(0.0, 0.0, 1.0))
    w1 = Wire(BRepBuilderAPI_MakeWire(Edge(BRepBuilderAPI_MakeEdge(gp_Circ(ax1, 1.0)))))
    w2 = Wire(BRepBuilderAPI_MakeWire(Edge(BRepBuilderAPI_MakeEdge(gp_Circ(ax2, 1.0)))))

    loft = BRepOffsetAPI_ThruSections(true, false)  # solid, not ruled
    AddWire(loft, w1)
    AddWire(loft, w2)
    Build(loft)
    @test IsDone(loft)
    result = Shape(loft)
    @test !IsNull(result)
end

@testset "BRepOffsetAPI_MakePipe (sweep, 1:1)" begin
    # Sweep a circle along a straight spine
    spine_edge = Edge(BRepBuilderAPI_MakeEdge(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(0.0, 0.0, 2.0)))
    spine = Wire(BRepBuilderAPI_MakeWire(spine_edge))
    profile = Edge(BRepBuilderAPI_MakeEdge(
        gp_Circ(gp_Ax2(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0)), 0.5)))

    pipe = BRepOffsetAPI_MakePipe(spine, profile)
    @test IsDone(pipe)
    result = Shape(pipe)
    @test !IsNull(result)
    @test isa(ErrorOnSurface(pipe), Float64)
end

@testset "BRepOffsetAPI_MakeOffsetShape (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))
    m = BRepOffsetAPI_MakeOffsetShape()
    PerformBySimple(m, box, 0.1)
    @test IsDone(m)
    result = Shape(m)
    @test !IsNull(result)
end
