# Generated USD Fixtures

These fixtures are generated from the adjacent USDA sources with the installed
USD command line tools. They exercise the pure Swift binary readers against
real crate output while keeping the source scene human-readable.

Regenerate the USDC fixtures with:

```bash
usdcat -o Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usdc
```

The generated files are USD crates containing small `Mesh` prims with triangle
topology. `translated_mesh.usdc` also verifies `xformOpOrder` plus a parent
`xformOp:translate` authored by OpenUSD. `animated_mesh.usdc` verifies that a
mesh attribute with `timeSamples` and no `default` can still be imported as a
mesh exchange snapshot. `blocked_values_mesh.usdc` verifies that blocked
defaults and blocked samples are treated as absent mesh exchange values.
`blocked_required_default_mesh.usdc` verifies that a blocked required mesh
attribute is reported as missing instead of being decoded as an unsupported
value type.
