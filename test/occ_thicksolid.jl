@testset "BRepOffsetAPI_MakeThickSolid (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(2.0, 2.0, 2.0))

    # MakeThickSolidBySimple expects a NON-CLOSED shell or face as input
    # (per the header doc: "Non-closed shell or face is expected as input"),
    # not a closed solid -- thicken a single planar face of the box instead.
    fex0 = TopExp_Explorer()
    Init(fex0, box, TopAbs_FACE())
    oneface = TopoDS_Face(Current(fex0))

    ts = BRepOffsetAPI_MakeThickSolid()
    @test ts isa BRepOffsetAPI_MakeThickSolid
    MakeThickSolidBySimple(ts, oneface, 0.1)
    @test IsDone(ts) == true
    hollow = Shape(ts)
    @test !IsNull(hollow)

    # MakeThickSolidByJoin: hollow the closed box solid while removing one face
    # (the documented use case -- closing faces are only supported here, not
    # in MakeThickSolidBySimple).
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    topface = TopoDS_Face(Current(fex))

    closing = TopTools_ListOfShape()
    Append(closing, topface)

    ts2 = BRepOffsetAPI_MakeThickSolid()
    MakeThickSolidByJoin(ts2, box, closing, -0.1, 1.0e-3,
                          BRepOffset_Skin(), false, false, GeomAbs_Arc(), false)
    @test IsDone(ts2) == true
    @test !IsNull(Shape(ts2))

    mods = Modified(ts2, topface)
    @test mods isa TopTools_ListOfShape

    @test BRepOffset_Skin() isa Integer
    @test BRepOffset_Pipe() isa Integer
    @test BRepOffset_RectoVerso() isa Integer
end
