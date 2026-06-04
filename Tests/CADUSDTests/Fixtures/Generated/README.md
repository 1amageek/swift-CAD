# Generated USD Fixtures

These fixtures are generated from the adjacent USDA sources with the installed
USD command line tools. They exercise the pure Swift binary readers against
real crate output while keeping the source scene human-readable.

Regenerate `minimal_mesh.usdc` with:

```bash
usdcat -o Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc
```

The generated file is a USD crate containing one `Mesh` prim with triangle
topology, `metersPerUnit = 1`, `upAxis = "Z"`, and `defaultPrim = "Triangle"`.
