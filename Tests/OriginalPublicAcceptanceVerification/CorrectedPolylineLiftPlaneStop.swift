#if canImport(Darwin)
import Darwin
#endif
import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicLiftPlanePort

/// Reproduces the actual corrected-host decline at the exact public entry producer.
@main struct CorrectedPolylineLiftPlaneStop {
    typealias Admission = PolylineLiftProof.Admission
    typealias Source = OriginalPolylineRetainedAtlasLiftSnapshot<OriginalBoundaryCorrectionSnapshot>

    static func marker(_ value: StaticString) { print(value); fflush(nil) }

    static func main() throws {
        var a = try Admission(work: 8_388_608)
        let corrected = try PolylineAtlasLiftProof.shape(multi: false, using: &a).1
        let parameterCurve = SurfaceParameterCurve.polyline(PolylineLiftProof.points())
        let input = SurfaceLiftCurve3D(surface: .procedural(.originalBoundaryCorrected(corrected)),
            parameterCurve: parameterCurve)
        let plane = Surface3D.plane(.init(origin: .init(x: 0.5, y: 0, z: 0), normal: .unitX))
        let limits = try PolylineLiftProof.limits()
        let pcurve = try DefaultOriginalSourceBindingIssuer(provider: OriginalPolylinePcurveSnapshotProvider(
            maximumValueDepth: 32, maximumCoefficientDepth: 32)).bind(parameterCurve, limits: limits.source, using: &a)
        let f = pcurve.original.originalField
        let family = try PolylineAtlasLiftProof.prepared(OriginalBoundaryCorrectionSnapshotProvider(field: f,
            tolerance: .standard), input: input, pcurve: pcurve, using: &a)
        let issuer = DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
        let frame = try issuer.frame(family: family, limits: limits, using: &a)
        let cover = try issuer.issue(request: frame.fullSelection(limits: limits, using: &a),
            family: family, limits: limits, using: &a)
        try PolylineLiftProof.require(family.graphs.count == 3 && pcurve.original.originalCellCount == 3)
        let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a)
        let half = try f.dividing(one, two, using: &a), z = try f.dividing(one, f.integer(16, using: &a), using: &a)
        let first = pcurve.original.originalCellUpperBound(at: 0)
        // The positive root of t^2 + 2t - 1 is independently sqrt(2) - 1.
        try PolylineLiftProof.require(f.sign(of: first, using: &a) == .positive)
        let equation = try f.subtracting(f.adding(f.multiplying(first, first, using: &a),
            f.multiplying(two, first, using: &a), using: &a), one, using: &a)
        try PolylineLiftProof.require(f.sign(of: equation, using: &a) == .zero)
        try PolylineLiftProof.require(f.compare(first, one, using: &a) == .less)
        let expectedRoots = [first, first, one], curveRing = pcurve.original.originalPolynomials
        for cell in 0..<3 {
            let h = pcurve.original.originalCellHomogeneous(at: cell)
            try PolylineLiftProof.require(h.count == 4)
            let x = try curveRing.subtracting(h[0], curveRing.scaled(h[3], by: half, using: &a), using: &a)
            let factor = try curveRing.subtracting(curveRing.variable(0, using: &a),
                curveRing.constant(expectedRoots[cell], using: &a), using: &a)
            let division = try curveRing.divided(x, by: factor, using: &a)
            try PolylineLiftProof.require(curveRing.isZero(division.remainder, using: &a))
            try PolylineLiftProof.require(division.quotient.termCount == 1
                && division.quotient.terms[0].powers.allSatisfy { $0 == 0 })
            try PolylineLiftProof.require(f.sign(of: division.quotient.terms[0].coefficient, using: &a) != .zero)
            let denominator = try curveRing.evaluated(h[3], at: [expectedRoots[cell]], using: &a).value
            for axis in 0..<2 {
                let uv = try f.dividing(curveRing.evaluated(h[axis], at: [expectedRoots[cell]], using: &a).value,
                    denominator, using: &a)
                try PolylineLiftProof.require(f.compare(uv, half, using: &a) == .equal)
            }
        }
        for graph in family.graphs {
            let r = graph.polynomials
            try PolylineLiftProof.require(r.isZero(r.subtracting(graph.homogeneous[0],
                r.multiplying(r.variable(1, using: &a), graph.homogeneous[3], using: &a), using: &a), using: &a))
        }
        for t in [first, one] {
            let incidents = try cover.liftedPositionIncidents(at: [t, half, half], limits: limits, using: &a)
            try PolylineLiftProof.require(incidents.count == (try f.compare(t, first, using: &a) == .equal ? 2 : 1))
            for incident in incidents {
                let graph = incident.graph, r = graph.polynomials
                let denominator = try r.evaluated(graph.homogeneous[3], at: [t, half, half], using: &a).value
                for (axis, expected) in [half, half, z].enumerated() {
                    let actual = try f.dividing(r.evaluated(graph.homogeneous[axis], at: [t, half, half], using: &a).value,
                        denominator, using: &a)
                    try PolylineLiftProof.require(f.compare(actual, expected, using: &a) == .equal)
                }
            }
        }
        let planeSource = try DefaultOriginalSourceBindingIssuer(provider: OriginalPlaneSnapshotProvider(tolerance: .standard))
            .bind(plane, limits: limits.source, using: &a)
        let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot, OriginalExactScalarDomain>().issue(
            source: planeSource, field: f, firstLength: one, normalLength: one, limits: limits.source, using: &a)
        for (axis, expected) in [half, half, z].enumerated() {
            let actual = try f.adding(basis.origin[axis], f.adding(f.multiplying(z, basis.u[axis], using: &a),
                f.multiplying(f.negated(half, using: &a), basis.v[axis], using: &a), using: &a), using: &a)
            try PolylineLiftProof.require(f.compare(actual, expected, using: &a) == .equal)
        }
        marker("PASS actual corrected constructor/source/DI; complete three-segment roots sqrt2-1 and1 remain distinct; exact XYZ(.5,.5,1/16), sourceUV(.5,.5), planeUV(1/16,-.5)")
        for retaining in [false, true] {
            let result = try PublicLiftPlanePort.OriginalRetainedLiftPlanePublicProducer().resolve(curve: .surfaceLift(input),
                surface: plane, options: .init(), tolerance: .standard, retainingRelations: retaining)
            if let result {
                print("OBSERVED selected exact public producer accepted corrected host", retaining, "points", result.points.count)
                fflush(nil)
            } else {
                print("OBSERVED selected exact public producer declined corrected host", retaining, "result nil")
                fflush(nil)
            }
        }
    }
}
