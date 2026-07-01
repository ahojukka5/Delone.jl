@testset "BRepMesh_IncrementalMesh (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Constructor with shape + deflection auto-performs
    m = BRepMesh_IncrementalMesh(box, 0.1, false, 0.5, false)
    @test m isa BRepMesh_IncrementalMesh
    @test IsModified(m) isa Bool
    @test GetStatusFlags(m) isa Integer

    # Default constructor + explicit Perform
    m2 = BRepMesh_IncrementalMesh()
    @test m2 isa BRepMesh_IncrementalMesh
    # Perform on default-constructed mesh should not throw
    @test_nowarn Perform(m2)
    @test IsModified(m2) isa Bool
end

@testset "BRepAlgoAPI_Check (1:1)" begin
    box = Shape(BRepPrimAPI_MakeBox(1.0, 1.0, 1.0))

    # Single-shape constructor auto-performs
    c = BRepAlgoAPI_Check(box, true, false)
    @test c isa BRepAlgoAPI_Check
    @test IsValid(c) == true  # a simple box is valid

    # Default constructor + explicit Perform
    c2 = BRepAlgoAPI_Check()
    @test c2 isa BRepAlgoAPI_Check
    @test_nowarn Perform(c2)
    # IsValid on empty check should return true (no faulty shapes found)
    @test IsValid(c2) isa Bool
end
