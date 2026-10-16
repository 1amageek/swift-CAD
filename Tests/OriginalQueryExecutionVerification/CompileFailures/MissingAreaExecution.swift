import CADCore
@testable import CADGeometry
@testable import CADTopology

// Expected compile failure: each call omits the mandatory caller execution.
func missingAreaExecution(trim: CertifiedImplicitSurfaceParameterCurve,
    joined: CertifiedImplicitSurfaceParameterCurve, source: Surface3D,
    chart: SurfaceAreaParameterChartEncloser, tolerance: ModelingTolerance) throws {
    _ = try SurfaceAreaParameterChartEncloser(curve: .certifiedImplicit(trim),
        on: source, tolerance: tolerance)
    _ = try SurfaceAreaParameterChartEncloser(curve: .certifiedImplicit(joined),
        on: source, tolerance: tolerance)
    _ = try chart.intervalJet(over: ScalarInterval(lower: 0.5, upper: 0.5),
        tolerance: tolerance)
}
