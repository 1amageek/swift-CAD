import CADCore
import CADGeometry
@testable import CADTopology
import Testing

@Suite("Original rational pcurve seam bands")
struct CertifiedRationalPcurveSeamBandTests {
    private let tolerance = ModelingTolerance.standard

    /// S(u,v)=(u,v,1) has flux density 1/3 and Green primitive u/3.
    /// The original surface has two owning U spans meeting at u=1/2.
    /// With depth zero an uncertain seam cell is the entire curve, so removing
    /// its measure would return zero instead of these independent antiderivatives.
    @Test(.timeLimit(.minutes(1)), arguments: [
        "nearEndpoint", "interiorCrossing", "contact", "onSeam", "noCrossing",
    ])
    func completeOriginalSeamBandMeasureContainsLiteralIntegral(kind: String) throws {
        let delta = 1.0 / 1_073_741_824.0
        let curve: BSplineCurve2D
        let expected: Double
        switch kind {
        case "nearEndpoint":
            let lowerU = 0.5 - delta * (255.0 / 256.0)
            let upperU = 0.5 + delta / 256.0
            curve = Self.linearQuartic(lowerU: lowerU, upperU: upperU)
            expected = 1.0 / 6.0 - 127.0 * delta / 768.0
        case "interiorCrossing":
            curve = Self.linearQuartic(lowerU: 0.5 - delta, upperU: 0.5 + delta)
            expected = 1.0 / 6.0
        case "contact":
            // u(t)=1/2+delta*(t-1/2)^2, v(t)=t, including the interior contact.
            curve = BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.5 + delta / 4.0, y: 0.0),
                    Point2D(x: 0.5 - delta / 4.0, y: 0.5),
                    Point2D(x: 0.5 + delta / 4.0, y: 1.0),
                ]
            )
            expected = 1.0 / 6.0 + delta / 36.0
        case "onSeam":
            curve = Self.linearQuartic(lowerU: 0.5, upperU: 0.5, weight: 2.0)
            expected = 1.0 / 6.0
        case "noCrossing":
            curve = Self.linearQuartic(lowerU: 0.75, upperU: 0.75 + delta)
            expected = 1.0 / 4.0 + delta / 6.0
        default:
            Issue.record("The independent seam integral fixture was not selected.")
            return
        }
        try curve.validate(tolerance: tolerance)
        let field = try Self.field(tolerance: tolerance)
        let optional = try CertifiedAnalyticPcurveFluxIntegrator(maximumDepth: 0)
            .rationalSurfaceBounds(
                for: .bSpline(curve),
                field: field,
                uBase: 0.0,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(optional)
        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.width <= tolerance.distance)
        #expect(bounds.lower > 0.1)
    }

    /// Unequal positive original weights change the speed but not the straight
    /// image u=1/4+v/2. Integral (1/4+v/2)/3 dv from zero to one is 1/6.
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func unequalOriginalWeightsRetainCrossingFluxAndDirection(backwards: Bool) throws {
        let original = Self.unequalWeightCurve()
        try original.validate(tolerance: tolerance)
        let curve = backwards ? try original.reversed(tolerance: tolerance) : original
        let optional = try CertifiedAnalyticPcurveFluxIntegrator()
            .rationalSurfaceBounds(
                for: .bSpline(curve),
                field: try Self.field(tolerance: tolerance),
                uBase: 0.0,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(optional)
        let expected = backwards ? -1.0 / 6.0 : 1.0 / 6.0
        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.width <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func unresolvedBandCannotAuthorizeAnInsufficientFluxWidth() throws {
        let delta = 1.0 / 1_073_741_824.0
        let requestedWidth = 1.0e-16
        let curve = Self.linearQuartic(lowerU: 0.5 - delta, upperU: 0.5 + delta)
        let field = try Self.field(tolerance: tolerance)
        do {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumDepth: 0)
                .rationalSurfaceBounds(
                    for: .bSpline(curve),
                    field: field,
                    uBase: 0.0,
                    requestedWidth: requestedWidth,
                    tolerance: tolerance
                )
            Issue.record("An unresolved seam band must still prove the requested flux width.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
            #expect((error.residual ?? 0.0) > requestedWidth)
            #expect(error.message.contains("two-dimensional proof depth"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalSeamCellWorkExhaustionRemainsTyped() throws {
        let field = try Self.field(tolerance: tolerance)
        do {
            _ = try CertifiedAnalyticPcurveFluxIntegrator(maximumWorkItems: 1)
                .rationalSurfaceBounds(
                    for: .bSpline(Self.unequalWeightCurve()),
                    field: field,
                    uBase: 0.0,
                    requestedWidth: tolerance.distance,
                    tolerance: tolerance
                )
            Issue.record("An unresolved seam band must not bypass original cell work accounting.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == 2.0)
            #expect(error.message.contains("Bernstein-cell budget"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledOriginalRationalFluxRefusesPublication() async throws {
        let tolerance = tolerance
        let field = try Self.field(tolerance: tolerance)
        let curve = SurfaceParameterCurve.bSpline(Self.unequalWeightCurve())
        let task = Task<Void, Error> {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try CertifiedAnalyticPcurveFluxIntegrator().rationalSurfaceBounds(
                for: curve,
                field: field,
                uBase: 0.0,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        }
        do {
            try await task.value
            Issue.record("A cancelled original rational flux query must not publish bounds.")
        } catch is CancellationError {
            #expect(task.isCancelled)
        }
    }

    private static func linearQuartic(
        lowerU: Double,
        upperU: Double,
        weight: Double = 1.0
    ) -> BSplineCurve2D {
        BSplineCurve2D(
            degree: 4,
            knots: [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: (0...4).map { index in
                let fraction = Double(index) / 4.0
                return Point2D(x: lowerU + (upperU - lowerU) * fraction, y: fraction)
            },
            weights: Array(repeating: weight, count: 5)
        )
    }

    private static func unequalWeightCurve() -> BSplineCurve2D {
        BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [Point2D(x: 0.25, y: 0.0), Point2D(x: 0.75, y: 1.0)],
            weights: [1.0, 2.0]
        )
    }

    private static func field(
        tolerance: ModelingTolerance
    ) throws -> CertifiedRationalBezierSurfaceFluxIntegrator.PreparedField {
        let coordinates = [0.0, 0.5, 1.0]
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.5, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [0.0, 1.0].map { v in
                coordinates.map { Point3D(x: $0, y: v, z: 1.0) }
            }
        )
        try surface.validate(tolerance: tolerance)
        let prepared = try CertifiedRationalBezierSurfaceFluxIntegrator().preparedField(
            surface: surface,
            reference: .origin,
            tolerance: tolerance
        )
        return try #require(prepared)
    }
}
