@testset "OCC I/O: BRepTools BREP round-trip (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(gp_Pnt(0.0, 0.0, 0.0), gp_Pnt(1.0, 1.0, 1.0)))

    function count_faces(shape)
        ex = TopExp_Explorer(); Init(ex, shape, 4)   # 4 = TopAbs_FACE
        n = 0; while More(ex); n += 1; Next(ex); end
        return n
    end

    f = tempname() * ".brep"
    @test BRepTools_Write(box, f)
    s2 = TopoDS_Shape()
    @test BRepTools_Read(s2, f)
    @test count_faces(s2) == 6
    rm(f; force=true)
end

@testset "OCC I/O: STEP reader (STEPControl_Reader)" begin
    r = STEPControl_Reader()
    status = ReadFile(r, STEP)
    @test status == 1    # IFSelect_RetDone = 1
    TransferRoots(r)
    @test NbShapes(r) >= 1
    shape = OneShape(r)
    @test !IsNull(shape)
end
