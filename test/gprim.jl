@testset "Box3d (constructor / PMin / PMax)" begin
    pmin = Netgen.Point3d(1.0, 2.0, 3.0)
    pmax = Netgen.Point3d(4.0, 5.0, 6.0)
    b = Box3d(pmin, pmax)
    bmin = Netgen.PMin(b)
    bmax = Netgen.PMax(b)
    @test Netgen.MinX(b) ≈ 1.0
    @test Netgen.MaxZ(b) ≈ 6.0
    @test Netgen.IsIn(b, Netgen.Point3d(2.0, 3.0, 4.0)) != 0
    @test Netgen.IsIn(b, Netgen.Point3d(10.0, 10.0, 10.0)) == 0
end

@testset "Point3dTree (new_point3dtree / Insert / GetIntersecting)" begin
    pmin = Netgen.Point3d(0.0, 0.0, 0.0)
    pmax = Netgen.Point3d(10.0, 10.0, 10.0)
    tree = new_point3dtree(pmin, pmax)
    Netgen.Insert(tree, Netgen.Point3d(1.0, 1.0, 1.0), 42)
    Netgen.Insert(tree, Netgen.Point3d(9.0, 9.0, 9.0), 99)
    hits = Netgen.GetIntersecting(tree,
                                  Netgen.Point3d(0.5, 0.5, 0.5),
                                  Netgen.Point3d(2.0, 2.0, 2.0))
    @test 42 in hits
    @test !(99 in hits)
end
