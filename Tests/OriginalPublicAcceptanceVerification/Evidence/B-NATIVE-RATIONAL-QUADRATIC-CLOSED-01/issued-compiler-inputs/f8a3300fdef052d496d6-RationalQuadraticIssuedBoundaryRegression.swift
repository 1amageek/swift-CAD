import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters
@testable import PublicLiftPlane
@testable import PublicCoonsBoundary
import CADTopology
import CADKernel

/// One changed issued-boundary path; the retained lower solver is a historical premise.
@main struct RationalQuadraticIssuedBoundaryRegression {
    typealias F = OriginalExactScalarDomain
    typealias Field = PublicLiftPlane.ExactAlgebraicScalarDomain<F>

    static func sourceAuthority() throws {
        var a = try PolylineLiftProof.Admission(work: 80_000_000)
        let base = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &a)
        let field = try Field.base(field: base, maximumExtensionLevel: 32, using: &a)
        let curve = BSplineCurve2D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [.init(x: 0.5, y: 0.25), .init(x: 0.25, y: 0.25), .init(x: 0, y: 0)],
            weights: [1, 3, 1])
        let source = try DefaultOriginalSourceBindingIssuer(provider: PublicCoonsBoundary.OriginalBSplinePcurveSnapshotProvider(tolerance: .standard))
            .bind(curve, limits: .init(remainingSourceDepth: 8), using: &a)
        let receipt = try PublicCoonsBoundary.DefaultOriginalRationalQuadraticBoundaryIssuer<BSplineCurve2D, Field>()
            .issue(source: source, field: field, limits: .init(remainingSourceDepth: 8), using: &a)
        try PolylineLiftProof.require(receipt.law.source.original == curve)
        let ring = receipt.law.polynomials
        let s = try ring.variable(0, using: &a), s2 = try ring.multiplying(s, s, using: &a)
        func constant(_ value: Double) throws -> ExactPolynomial<Field> {
            try ring.constant(field.binary64(exactly: value, using: &a), using: &a)
        }
        func linear(_ c: Double, _ gain: Double, _ square: Double) throws -> ExactPolynomial<Field> {
            try ring.adding(ring.adding(constant(c), ring.multiplying(constant(gain), s, using: &a), using: &a),
                ring.multiplying(constant(square), s2, using: &a), using: &a)
        }
        let expected = try [linear(0.5, 0.5, -1), linear(0.25, 1, -1.25), constant(0), linear(1, 4, -4)]
        let h = receipt.law.homogeneous
        for axis in 0..<4 {
            let lhs = try ring.multiplying(h[axis], expected[3], using: &a)
            let rhs = try ring.multiplying(expected[axis], h[3], using: &a)
            try PolylineLiftProof.require(ring.equals(lhs, rhs, using: &a))
        }
        let zero = try constant(0)
        for residual in receipt.identityResiduals { try PolylineLiftProof.require(ring.equals(residual, zero, using: &a)) }
        print("PASS OriginalExactScalarDomain rational quadratic source coefficients and complete source authority")
    }

    static func detachedResult() throws -> OriginalIssuedGraphFaceClippedParameters<
        BSplineCurve3D, OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, F>, CoonsHoleBoundaryProbe.CurveCover,
        OriginalCoonsAtlasSnapshot, OriginalRationalChartReceipt<OriginalCoonsAtlasSnapshot, Int, F>, CoonsHoleBoundaryProbe.SurfaceCover> {
        var preparation = try PolylineLiftProof.Admission(work: 80_000_000)
        let host = try PolylineAtlasLiftProof.shape(multi: true, using: &preparation).0
        let face = try CoonsHoleBoundaryProbe.face(host: host)
        let field = try F(maximumValueDepth: 32, maximumCoefficientDepth: 32, using: &preparation)
        let limits = try PolylineLiftProof.limits()
        let raw = try CoonsHoleBoundaryProbe.raw(host: host, field: field, limits: limits, using: &preparation)
        let binding = try OriginalFaceSurfaceBinding.coons(raw.second.source, limits: limits.source, using: &preparation)
        let source = try OriginalIssuedGraphBoundarySource.secondSurface(raw, binding: binding, limits: limits, using: &preparation)
        var query = try PolylineLiftProof.Admission(work: 80_000_000)
        let result = try CADKernel.DefaultOriginalFaceBoundaryClipper().clip(source, to: face.1, in: face.0,
            selection: .closed, domainLimits: limits,
            cellLimits: .init(maximumStoredCells: 20_000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20_000, maximumRootsPerStack: 100,
                maximumClosures: 20_000, maximumAttachmentPieces: 100_000, maximumComponents: 1_000), using: &query)
        try PolylineLiftProof.require(result.faceID == face.1 && result.loops.count == 2 &&
            result.parameters.boundary.source.raw.second.source.owner === raw.second.source.owner)
        try PolylineLiftProof.require(result.parameters.boundary.preparedLoops.count == 2)
#if !hasFeature(Embedded)
        print("ISSUED query work", query.ledger.work, "storage", query.ledger.storageBytes)
#endif
        return result
    }

    static func main() throws {
        try sourceAuthority()
        let retained = try detachedResult()
        var independent = try PolylineLiftProof.Admission(work: 80_000_000)
        try CoonsHoleBoundaryAcceptance.verify(retained, using: &independent)
        try PolylineLiftProof.require(retained.parameters.refinements.map { $0.parameters.pairOrdinal } == [0, 1, 2, 3])
        print("PASS issued Coons closed: all four raw/refined ordinals, all terminal material iff, spans, detached lifetime")
    }
}
