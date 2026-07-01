@testset "BRepOffsetAPI_DraftAngle (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))
    dir = gp_Dir(0.0, 0.0, 1.0)
    neutral = gp_Pln(gp_Pnt(0.0, 0.0, 0.0), gp_Dir(0.0, 0.0, 1.0))

    # Try each face as the draft target; a vertical side wall should succeed
    # against a vertical pull direction (the bottom/top caps are degenerate
    # for this direction and may legitimately fail) -- robust to face order.
    fex = TopExp_Explorer()
    Init(fex, box, TopAbs_FACE())
    succeeded = false
    while More(fex)
        face = TopoDS_Face(Current(fex))
        da = BRepOffsetAPI_DraftAngle(box)
        try
            Add(da, face, dir, 0.1, neutral, true)
            if AddDone(da)
                Build(da)
                @test !IsNull(Shape(da))
                succeeded = true
                break
            end
        catch
            # face/direction combination not draftable; try the next face
        end
        Next(fex)
    end
    @test succeeded == true

    # Default constructor + Init + Clear shouldn't throw
    da2 = BRepOffsetAPI_DraftAngle()
    Init(da2, box)
    @test_nowarn Clear(da2)
end
