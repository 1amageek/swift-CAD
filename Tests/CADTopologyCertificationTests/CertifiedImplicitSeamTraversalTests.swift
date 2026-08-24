import CADCore
@testable import CADGeometry
@testable import CADTopology
import Testing

@Suite("Certified Implicit Seam Traversal")
struct CertifiedImplicitSeamTraversalTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func seamTraversalCoversTheWholeLocalCurveWithoutGaps() throws {
        let fixture = try closedPlanePcurve()
        let seam = try pcurve(
            from: 0.8,
            to: 1.2,
            fixture: fixture
        )
        let reversed = try pcurve(
            from: 1.2,
            to: 0.8,
            fixture: fixture
        )

        let forwardSegments = try seam.canonicalTraversalSegments(
            tolerance: tolerance
        )
        let reversedSegments = try reversed.canonicalTraversalSegments(
            tolerance: tolerance
        )
        #expect(forwardSegments.count == 2)
        #expect(reversedSegments.count == 2)
        #expect(forwardSegments.allSatisfy { $0.direction == .forward })
        #expect(reversedSegments.allSatisfy { $0.direction == .reversed })

        for curve in [seam, reversed] {
            let enclosures = try CertifiedSurfaceParameterCurveEncloser()
                .enclosures(
                    for: .certifiedImplicit(curve),
                    maximumWidth: 0.1,
                    tolerance: tolerance
                )
            #expect(enclosures.isEmpty == false)
            #expect(abs(enclosures[0].lowerFraction) <= tolerance.relative)
            #expect(abs(enclosures[enclosures.count - 1].upperFraction - 1.0)
                <= tolerance.relative)
            #expect(zip(enclosures, enclosures.dropFirst()).allSatisfy { pair in
                abs(pair.0.upperFraction - pair.1.lowerFraction)
                    <= tolerance.relative
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func seamAreaAndRationalFluxEqualCanonicalTailPlusHead() throws {
        let fixture = try closedPlanePcurve()
        let seam = try pcurve(from: 0.8, to: 1.2, fixture: fixture)
        let reversed = try pcurve(from: 1.2, to: 0.8, fixture: fixture)
        let tail = try pcurve(from: 0.8, to: 1.0, fixture: fixture)
        let head = try pcurve(from: 0.0, to: 0.2, fixture: fixture)
        let full = try pcurve(from: 0.0, to: 1.0, fixture: fixture)
        let fullReversed = try pcurve(from: 1.0, to: 0.0, fixture: fixture)
        let requestedWidth = 1.0e-5

        let areaIntegrator = SurfaceParameterCurveAreaIntegrator()
        let seamArea = try areaIntegrator.bounds(
            for: .certifiedImplicit(seam),
            uShift: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let reversedArea = try areaIntegrator.bounds(
            for: .certifiedImplicit(reversed),
            uShift: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        )
        let tailArea = try areaIntegrator.bounds(
            for: .certifiedImplicit(tail),
            uShift: 0.0,
            requestedWidth: requestedWidth * 0.5,
            tolerance: tolerance
        )
        let headArea = try areaIntegrator.bounds(
            for: .certifiedImplicit(head),
            uShift: 0.0,
            requestedWidth: requestedWidth * 0.5,
            tolerance: tolerance
        )
        expectOverlap(
            lower: seamArea.lower,
            upper: seamArea.upper,
            comparisonLower: tailArea.lower + headArea.lower,
            comparisonUpper: tailArea.upper + headArea.upper
        )
        expectOverlap(
            lower: reversedArea.lower,
            upper: reversedArea.upper,
            comparisonLower: -seamArea.upper,
            comparisonUpper: -seamArea.lower
        )

        let field = try #require(
            try CertifiedRationalBezierSurfaceFluxIntegrator().preparedField(
                surface: fixture.surface,
                reference: Point3D(x: 0.0, y: 0.0, z: -1.0),
                tolerance: tolerance
            )
        )
        let fluxIntegrator = CertifiedAnalyticPcurveFluxIntegrator()
        let seamFlux = try #require(try fluxIntegrator.rationalSurfaceBounds(
            for: .certifiedImplicit(seam),
            field: field,
            uBase: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ))
        let reversedFlux = try #require(try fluxIntegrator.rationalSurfaceBounds(
            for: .certifiedImplicit(reversed),
            field: field,
            uBase: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ))
        let tailFlux = try #require(try fluxIntegrator.rationalSurfaceBounds(
            for: .certifiedImplicit(tail),
            field: field,
            uBase: 0.0,
            requestedWidth: requestedWidth * 0.5,
            tolerance: tolerance
        ))
        let headFlux = try #require(try fluxIntegrator.rationalSurfaceBounds(
            for: .certifiedImplicit(head),
            field: field,
            uBase: 0.0,
            requestedWidth: requestedWidth * 0.5,
            tolerance: tolerance
        ))
        let fullFlux = try #require(try fluxIntegrator.rationalSurfaceBounds(
            for: .certifiedImplicit(full),
            field: field,
            uBase: 0.0,
            requestedWidth: requestedWidth,
            tolerance: tolerance
        ))
        let fullReversedFlux = try #require(
            try fluxIntegrator.rationalSurfaceBounds(
                for: .certifiedImplicit(fullReversed),
                field: field,
                uBase: 0.0,
                requestedWidth: requestedWidth,
                tolerance: tolerance
            )
        )
        expectOverlap(
            lower: seamFlux.lower,
            upper: seamFlux.upper,
            comparisonLower: tailFlux.lower + headFlux.lower,
            comparisonUpper: tailFlux.upper + headFlux.upper
        )
        expectOverlap(
            lower: reversedFlux.lower,
            upper: reversedFlux.upper,
            comparisonLower: -seamFlux.upper,
            comparisonUpper: -seamFlux.lower
        )
        let expectedMagnitude = Double.pi / 3.0
        let fullMidpoint = fullFlux.lower
            + (fullFlux.upper - fullFlux.lower) * 0.5
        #expect(fullFlux.upper - fullFlux.lower <= requestedWidth)
        #expect(abs(abs(fullMidpoint) - expectedMagnitude) <= requestedWidth)
        expectOverlap(
            lower: fullReversedFlux.lower,
            upper: fullReversedFlux.upper,
            comparisonLower: -fullFlux.upper,
            comparisonUpper: -fullFlux.lower
        )
    }

    private func pcurve(
        from start: Double,
        to end: Double,
        fixture: (intersection: CertifiedImplicitIntersectionCurve, surface: BSplineSurface3D)
    ) throws -> CertifiedImplicitSurfaceParameterCurve {
        try CertifiedImplicitSurfaceParameterCurve(
            intersection: fixture.intersection,
            role: .second,
            startFraction: start,
            endFraction: end,
            tolerance: tolerance
        )
    }

    private func closedPlanePcurve() throws -> (
        intersection: CertifiedImplicitIntersectionCurve,
        surface: BSplineSurface3D
    ) {
        let plane = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.5, y: -1.5, z: 0.0),
                    Point3D(x: 1.5, y: -1.5, z: 0.0),
                ],
                [
                    Point3D(x: -1.5, y: 1.5, z: 0.0),
                    Point3D(x: 1.5, y: 1.5, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.25], [0.8, 1.0]]
        )
        let sphere = try AnalyticSurfaceBSplineBuilder().surface(
            for: CanonicalAnalyticSurface(.analytic(.sphere(
                center: .origin,
                radius: 1.0
            ))),
            boundedBy: plane,
            periodicSeamOffset: Double.pi * 0.125,
            tolerance: tolerance
        )
        let exact = try #require(try ExactIsoparametricPlanarIntersectionGraph
            .certified(
                first: sphere,
                second: plane,
                tolerance: tolerance
            )
        )
        let domains = [
            sphere.uDomain,
            sphere.vDomain,
            plane.uDomain,
            plane.vDomain,
        ]
        let cells = try exact.cells.map { source in
            let bounds = try zip(source.normalizedBounds, domains).map {
                normalized, domain in
                try ScalarInterval(
                    lower: actual(normalized.lower, in: domain),
                    upper: actual(normalized.upper, in: domain)
                )
            }
            return try CertifiedImplicitIntersectionGraphCell(
                parameterBox: SurfaceIntersectionParameterBox(
                    firstU: bounds[0],
                    firstV: bounds[1],
                    secondU: bounds[2],
                    secondV: bounds[3]
                ),
                freeParameter: source.freeParameter,
                direction: .forward,
                lowerAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                midpointAnchor: exact.actualParameterPair(
                    in: source,
                    at: 0.5,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                upperAnchor: exact.actualParameterPair(
                    in: source,
                    at: 1.0,
                    first: sphere,
                    second: plane,
                    tolerance: tolerance
                ),
                firstSurface: sphere,
                secondSurface: plane,
                tolerance: tolerance
            )
        }
        let intersection = try CertifiedImplicitIntersectionCurve(
            firstSurface: sphere,
            secondSurface: plane,
            cells: cells,
            isClosed: true,
            tolerance: tolerance
        )
        return (intersection, plane)
    }

    private func actual(
        _ normalized: Double,
        in domain: ParameterDomain
    ) -> Double {
        guard case let .closed(lower, upper) = domain else { return .nan }
        return lower + (upper - lower) * normalized
    }

    private func expectOverlap(
        lower: Double,
        upper: Double,
        comparisonLower: Double,
        comparisonUpper: Double
    ) {
        #expect(lower <= comparisonUpper)
        #expect(upper >= comparisonLower)
    }
}
