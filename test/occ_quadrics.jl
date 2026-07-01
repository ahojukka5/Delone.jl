@testset "gp_Cylinder (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax3 = gp_Ax3(origin, gp_Dir(0.0, 0.0, 1.0))

    c = gp_Cylinder(ax3, 2.0)
    @test c isa gp_Cylinder
    @test Radius(c) ≈ 2.0
    @test Location(c) isa gp_Pnt
    @test Position(c) isa gp_Ax3
    @test Axis(c) isa gp_Ax1
    @test XAxis(c) isa gp_Ax1
    @test YAxis(c) isa gp_Ax1
    @test Direct(c) isa Bool

    SetRadius(c, 3.5)
    @test Radius(c) ≈ 3.5

    newloc = gp_Pnt(1.0, 2.0, 3.0)
    SetLocation(c, newloc)
    @test Location(c) isa gp_Pnt

    SetPosition(c, ax3)
    SetAxis(c, gp_Ax1(origin, gp_Dir(1.0, 0.0, 0.0)))
end

@testset "gp_Cone (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax3 = gp_Ax3(origin, gp_Dir(0.0, 0.0, 1.0))

    c = gp_Cone(ax3, 0.3, 1.0)
    @test c isa gp_Cone
    @test SemiAngle(c) ≈ 0.3
    @test RefRadius(c) ≈ 1.0

    apex = Apex(c)
    @test apex isa gp_Pnt

    @test Location(c) isa gp_Pnt
    @test Position(c) isa gp_Ax3
    @test Axis(c) isa gp_Ax1
    @test XAxis(c) isa gp_Ax1
    @test YAxis(c) isa gp_Ax1
    @test Direct(c) isa Bool

    SetRadius(c, 2.0)
    @test RefRadius(c) ≈ 2.0
    SetSemiAngle(c, 0.5)
    @test SemiAngle(c) ≈ 0.5
end

@testset "gp_Sphere (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax3 = gp_Ax3(origin, gp_Dir(0.0, 0.0, 1.0))

    s = gp_Sphere(ax3, 1.0)
    @test s isa gp_Sphere
    @test Area(s) ≈ 4π atol=1e-10
    @test Volume(s) ≈ (4π / 3) atol=1e-10
    @test Radius(s) ≈ 1.0

    @test Location(s) isa gp_Pnt
    @test Position(s) isa gp_Ax3
    @test XAxis(s) isa gp_Ax1
    @test YAxis(s) isa gp_Ax1
    @test Direct(s) isa Bool

    SetRadius(s, 2.0)
    @test Radius(s) ≈ 2.0
    @test Area(s) ≈ 4π * 4 atol=1e-10
end

@testset "gp_Torus (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax3 = gp_Ax3(origin, gp_Dir(0.0, 0.0, 1.0))

    t = gp_Torus(ax3, 3.0, 1.0)
    @test t isa gp_Torus
    @test MajorRadius(t) ≈ 3.0
    @test MinorRadius(t) ≈ 1.0
    @test Area(t) > 0.0
    @test Volume(t) > 0.0

    @test Location(t) isa gp_Pnt
    @test Position(t) isa gp_Ax3
    @test Axis(t) isa gp_Ax1
    @test XAxis(t) isa gp_Ax1
    @test YAxis(t) isa gp_Ax1
    @test Direct(t) isa Bool

    SetMajorRadius(t, 4.0)
    @test MajorRadius(t) ≈ 4.0
    SetMinorRadius(t, 0.5)
    @test MinorRadius(t) ≈ 0.5
end
