import CADCore
import CADGeometry
import CADTopology

enum ExactExchangePolylinePcurveFixture {
    static func sheet() throws -> BRepModel {
        var model = try ExactExchangeAdvancedAnalyticFixture.ellipticalSheet()
        for loopID in model.loops.keys.sorted() {
            guard var loop = model.loops[loopID] else { continue }
            for index in loop.coedges.indices {
                guard let curve = loop.coedges[index].surfaceParameterCurve,
                      isLinear(curve) else { continue }
                let start = try curve.parameter(atNormalizedFraction: 0.0, tolerance: .standard)
                let midpoint = try curve.parameter(atNormalizedFraction: 0.5, tolerance: .standard)
                let end = try curve.parameter(atNormalizedFraction: 1.0, tolerance: .standard)
                loop.coedges[index].surfaceParameterCurve = .polyline([start, midpoint, end])
                model.loops[loopID] = loop
                try model.validate(level: .exact, tolerance: .standard)
                return model
            }
        }
        throw KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: .standard,
            message: "The exact polyline p-curve fixture requires a linear coedge."
        )
    }

    private static func isLinear(_ curve: SurfaceParameterCurve) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV:
            true
        case .harmonic, .sphericalGreatCircle, .polyline, .bSpline:
            false
        }
    }
}
