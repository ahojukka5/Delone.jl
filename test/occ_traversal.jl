@testset "OCC traversal: TopExp_Explorer (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))

    function count_shapes(shape, topabs_int)
        ex = TopExp_Explorer(); Init(ex, shape, topabs_int)
        n = 0; while More(ex); n += 1; Next(ex); end
        return n
    end

    @test count_shapes(box, 4) == 6    # TopAbs_FACE = 4; faces are not shared
    @test count_shapes(box, 6) == 24   # TopAbs_EDGE = 6; each of 12 edges visited once per adjacent face
    @test count_shapes(box, 7) == 48   # TopAbs_VERTEX = 7; each edge visit contributes 2 vertex visits

    # Cylinder: 3 faces (top, bottom, lateral), 3 edges, 2 vertices
    cyl = Shape(BRepPrimAPI_MakeCylinder(1.0, 2.0))
    @test count_shapes(cyl, 4) == 3

    # TopoDS_Iterator over box children
    it = TopoDS_Iterator(box)
    n = 0; while More(it); n += 1; Next(it); end
    @test n > 0
end
