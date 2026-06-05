# Generated USD Fixtures

These fixtures are generated from the adjacent USDA sources with the installed
USD command line tools. They exercise the pure Swift binary readers against
real crate output while keeping the source scene human-readable.

Regenerate the USDC fixtures with:

```bash
usdcat -o Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/minimal_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/point3d_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/point3d_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/point3d_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/translated_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/inverted_pivot_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/inverted_pivot_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/inverted_pivot_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/rotated_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/rotated_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/rotated_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/normals_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/normals_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/normals_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/left_handed_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/left_handed_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/left_handed_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/combined_rotation_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/combined_rotation_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/combined_rotation_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/orient_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/orient_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/orient_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/scalar_xform_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/scalar_xform_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/scalar_xform_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/extent_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/extent_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/extent_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/quad_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/quad_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/quad_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/subdivision_scheme_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/subdivision_scheme_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/subdivision_scheme_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/uv_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/uv_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/uv_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/display_color_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/display_color_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/display_color_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/animated_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/blocked_values_mesh.usdc
usdcat -o Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usdc Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usda
usdchecker Tests/CADUSDTests/Fixtures/Generated/blocked_required_default_mesh.usdc
```

The generated files are USD crates containing small `Mesh` prims with triangle
topology. `point3d_mesh.usdc` verifies double-precision Mesh point array
read-through. `translated_mesh.usdc` also verifies `xformOpOrder` plus a parent
`xformOp:translate` authored by OpenUSD. `inverted_pivot_mesh.usdc` verifies
paired inverse xform ops used for pivot transforms. `rotated_mesh.usdc` verifies
parent `xformOp:rotateX`, `xformOp:rotateY`, and `xformOp:rotateZ` handling.
`normals_mesh.usdc` verifies authored vertex-interpolated Mesh normals and
normal transform handling. `left_handed_mesh.usdc` verifies authored Mesh
orientation read-through.
`combined_rotation_mesh.usdc` verifies packed Euler `xformOp:rotateXYZ`
handling. `orient_mesh.usdc` verifies quaternion `xformOp:orient` handling for
`quatf`, `quatd`, and zero-quaternion identity behavior. `scalar_xform_mesh.usdc`
verifies scalar translate and scale xform ops. `extent_mesh.usdc` verifies
authored Mesh extent read-through. `quad_mesh.usdc` verifies non-triangle
face-vertex topology preservation. `subdivision_scheme_mesh.usdc` verifies
authored subdivision scheme token read-through. `uv_mesh.usdc` verifies
`primvars:st` texture coordinate value, index, and interpolation read-through.
`display_color_mesh.usdc` verifies `primvars:displayColor` and
`primvars:displayOpacity` value, index, and interpolation read-through.
`animated_mesh.usdc` verifies that a mesh attribute with `timeSamples` and no
`default` can still be imported as a mesh exchange snapshot.
`blocked_values_mesh.usdc` verifies that blocked defaults and blocked samples
are treated as absent mesh exchange values.
`blocked_required_default_mesh.usdc` verifies that a blocked required mesh
attribute is reported as missing instead of being decoded as an unsupported
value type.
