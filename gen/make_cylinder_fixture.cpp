// One-time generator for test/fixtures/cylinder.brep — a unit cylinder
// (radius 1, height 2) used to verify that geometry-aware refinement projects
// new nodes onto the true CAD surface (√(x²+y²) == 1 on the lateral face).
//
// This uses OpenCASCADE *modeling* (BRepPrimAPI), which is OCCT's API, not
// Netgen's — hence a standalone generator rather than something wrapped in
// libnetgen_cxxwrap. The .brep it produces is committed as a static fixture, so
// this only needs to run when regenerating it.
//
// Build & run (OCC = OCCT_jll artifact dir, e.g.
//   julia -e 'import OCCT_jll; print(OCCT_jll.artifact_dir)'):
//
//   clang++ -std=c++17 make_cylinder_fixture.cpp -o make_cylinder \
//     -I"$OCC/include/opencascade" -L"$OCC/lib" \
//     -lTKPrim -lTKBRep -lTKTopAlgo -lTKGeomBase -lTKG3d -lTKG2d -lTKMath -lTKernel \
//     -Wl,-rpath,"$OCC/lib"
//   ./make_cylinder ../test/fixtures/cylinder.brep
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepTools.hxx>
#include <TopoDS_Shape.hxx>
#include <iostream>

int main(int argc, char** argv) {
  const double R = 1.0, H = 2.0;
  TopoDS_Shape cyl = BRepPrimAPI_MakeCylinder(R, H).Shape();
  const char* out = (argc > 1) ? argv[1] : "cylinder.brep";
  if (!BRepTools::Write(cyl, out)) {
    std::cerr << "failed to write " << out << "\n";
    return 1;
  }
  std::cout << "wrote " << out << " (r=" << R << ", h=" << H << ")\n";
  return 0;
}
