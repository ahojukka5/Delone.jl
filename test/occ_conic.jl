@testset "gp_Parab (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax2 = gp_Ax2(origin, gp_Dir(0.0, 0.0, 1.0))

    p = gp_Parab(ax2, 2.0)
    @test p isa gp_Parab

    @test Focal(p) ≈ 2.0
    @test Parameter(p) ≈ 4.0  # parameter = 2 * focal

    f = Focus(p)
    @test f isa gp_Pnt

    d = Directrix(p)
    @test d isa gp_Ax1

    a = Axis(p)
    @test a isa gp_Ax1

    loc = Location(p)
    @test loc isa gp_Pnt

    @test XAxis(p) isa gp_Ax1
    @test YAxis(p) isa gp_Ax1

    # SetFocal
    SetFocal(p, 3.0)
    @test Focal(p) ≈ 3.0

    # SetLocation
    newloc = gp_Pnt(1.0, 0.0, 0.0)
    SetLocation(p, newloc)
    @test Location(p) isa gp_Pnt
end

@testset "gp_Hypr (1:1)" begin
    origin = gp_Pnt(0.0, 0.0, 0.0)
    ax2 = gp_Ax2(origin, gp_Dir(0.0, 0.0, 1.0))

    h = gp_Hypr(ax2, 3.0, 2.0)
    @test h isa gp_Hypr

    @test MajorRadius(h) ≈ 3.0
    @test MinorRadius(h) ≈ 2.0

    e = Eccentricity(h)
    @test e > 1.0  # hyperbola always has eccentricity > 1

    @test Focal(h) > 0.0
    @test Parameter(h) > 0.0

    @test Asymptote1(h) isa gp_Ax1
    @test Asymptote2(h) isa gp_Ax1

    ob = OtherBranch(h)
    @test ob isa gp_Hypr

    @test Focus1(h) isa gp_Pnt
    @test Focus2(h) isa gp_Pnt

    @test Axis(h) isa gp_Ax1
    @test Location(h) isa gp_Pnt

    # Setters
    SetMajorRadius(h, 4.0)
    @test MajorRadius(h) ≈ 4.0
    SetMinorRadius(h, 1.0)
    @test MinorRadius(h) ≈ 1.0
end
