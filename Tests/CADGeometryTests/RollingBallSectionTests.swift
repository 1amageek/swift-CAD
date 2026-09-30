import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Rolling-ball contact sections", .timeLimit(.minutes(1)))
struct RollingBallSectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test func completenessRefinesOnlyTheSurfaceWhoseEnclosureFailed() throws {
        let sphere = OffsetSurface3D(
            source: .analytic(.sphere(center: .origin, radius: 2)), distance: -0.2)
        let plane = OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)), distance: 0.2)
        let evaluator = try RollingBallSectionEvaluator(first: sphere, second: plane,
            intersection: intersection(sphere, plane), tolerance: tolerance)
        let blend = try evaluator.blendSurface(fromCurveParameter: 0.7, toCurveParameter: 4,
            options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
        let curved = try PreparedSurfaceDifferentialEncloser(
            surface: .procedural(.rollingBall(blend)), tolerance: tolerance)
        do {
            _ = try curved.intervalJet(over: SurfaceParameterBox(
                u: ScalarInterval(lower: 0, upper: 1), v: ScalarInterval(lower: 0, upper: 1)),
                tolerance: tolerance)
            Issue.record("The fixture must require local contact-radial enclosure refinement.")
        } catch let error as KernelError {
            #expect(error.code == .singularSystem || error.code == .intersectionFailure)
        }
        let distant = try PreparedSurfaceDifferentialEncloser(surface: .bSpline(.init(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [[Point3D(x: 0, y: 0, z: 10), Point3D(x: 1, y: 0, z: 10)],
                            [Point3D(x: 0, y: 1, z: 10), Point3D(x: 1, y: 1, z: 10)]],
            weights: [[1, 1], [1, 1]])), tolerance: tolerance)
        for reversed in [false, true] {
            let first = reversed ? distant : curved
            let second = reversed ? curved : distant
            var verifier = try ParametricSurfaceIntersectionCompletenessVerifier(
                first: first, second: second,
                domains: BoundedSurfaceParameterDomainMap(first: first.surface,
                    second: second.surface, tolerance: tolerance),
                options: .init(maximumSubdivisionDepth: 1, maximumSubdivisionCells: 3),
                tolerance: tolerance)
            // Only spine U can repair radial bounds; neither V nor the partner
            // coordinates may consume this three-cell refinement budget.
            var cells = 3
            var roots = 1
            let result = try verifier.firstUncoveredSeed(atlas: [], remainingCells: &cells,
                remainingRootAttempts: &roots)
            switch result {
            case .complete: break
            case .unresolved(let reason):
                #expect(reason.contains(reversed ? "[0, 0, 1, 0]" : "[1, 0, 0, 0]"))
            case .uncoveredSeed: Issue.record("Disjoint supports cannot produce a root.")
            }
            #expect(cells >= 0)
            #expect(roots == 1)
        }
    }

    @Test
    func curvedContactsRetainRadiusAndTangencyInBothOrdersAndOffsetSides() throws {
        let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        for distance in [-0.2, 0.2] {
            let sphericalOffset = OffsetSurface3D(source: sphere, distance: distance)
            let planarOffset = OffsetSurface3D(source: plane, distance: 0.2)
            for reverse in [false, true] {
                let first = reverse ? planarOffset : sphericalOffset
                let second = reverse ? sphericalOffset : planarOffset
                let component = try intersection(first, second)
                let evaluator: any RollingBallSectionEvaluating = try RollingBallSectionEvaluator(
                    first: first, second: second, intersection: component, tolerance: tolerance
                )
                // A circular intersection has a native angular domain, not [0, 1].
                for parameter in [0.0, 0.7, 2.5, 4.0, 6.0] {
                    let section = try evaluator.section(atCurveParameter: parameter)
                    let expectedCenterRadius = sqrt(pow(2 + distance, 2) - 0.04)
                    #expect(abs(hypot(section.center.x, section.center.y) - expectedCenterRadius)
                            <= tolerance.distance)
                    #expect(abs(section.center.z - 0.2) <= tolerance.distance)
                    #expect(section.maximumContactResidual <= tolerance.distance)
                    let sphericalContact = reverse ? section.secondContactPoint : section.firstContactPoint
                    let planarContact = reverse ? section.firstContactPoint : section.secondContactPoint
                    #expect(abs((sphericalContact - .origin).length - 2) <= tolerance.distance)
                    #expect(abs(planarContact.z) <= tolerance.distance)
                    for fraction in [0.0, 0.1, 0.3, 0.5, 0.8, 1.0] {
                        let point = try section.arc.point(at: fraction, tolerance: tolerance)
                        #expect(abs((point - section.center).length - 0.2) <= tolerance.distance)
                    }
                    for (fraction, source, contactParameter, contactPoint) in [
                        (0.0, first.source, section.firstContactParameter, section.firstContactPoint),
                        (1.0, second.source, section.secondContactParameter, section.secondContactPoint)
                    ] {
                        let differential = try section.arc.differentialGeometry(
                            at: fraction, tolerance: tolerance
                        )
                        let normal = try source.normal(
                            u: contactParameter.u, v: contactParameter.v, tolerance: tolerance
                        )
                        #expect((differential.position - contactPoint).length <= tolerance.distance)
                        #expect(abs(differential.tangent.dot(normal)) <= tolerance.angle)
                    }
                }
            }
        }
    }

    @Test
    func contactRailsStayOnOriginalSurfacesThroughTrimmingAndPersistence() throws {
        let sphere = OffsetSurface3D(
            source: .analytic(.sphere(center: .origin, radius: 2)), distance: -0.2
        )
        let plane = OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)), distance: 0.2
        )
        let component = try intersection(sphere, plane)
        let evaluator: any RollingBallSectionEvaluating = try RollingBallSectionEvaluator(
            first: sphere, second: plane, intersection: component, tolerance: tolerance
        )
        let options = CurveSurfaceCorrespondenceValidationOptions(
            maximumSubdivisionDepth: 20, maximumCellCount: 65_536
        )
        for role in [SurfaceIntersectionSurfaceRole.first, .second] {
            let lift = try evaluator.contactCurve(
                on: role, fromCurveParameter: 0.7, toCurveParameter: 4.0, options: options
            )
            let curve = Curve3D.surfaceLift(lift)
            let restored = try JSONDecoder().decode(Curve3D.self, from: JSONEncoder().encode(curve))
            #expect(restored == curve)
            try restored.validate(tolerance: tolerance)
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let section = try evaluator.section(atCurveParameter: 0.7 + 3.3 * fraction)
                let expected = role == .first ? section.firstContactPoint : section.secondContactPoint
                let point = try restored.point(at: fraction, tolerance: tolerance)
                #expect((point - expected).length <= tolerance.distance)
                #expect(abs((point - section.center).length - 0.2) <= tolerance.distance)
                let normal = role == .first ? (point - .origin) / 2 : .unitZ
                let differential = try lift.differentialGeometry(
                    atNormalizedFraction: fraction, tolerance: tolerance
                )
                #expect(abs(differential.firstDerivative.dot(normal)) <= tolerance.distance)
                #expect(differential.firstDerivative.length > tolerance.distance)
            }
        }
        #expect(throws: (any Error).self) {
            try evaluator.contactCurve(on: .first, fromCurveParameter: 4, toCurveParameter: 0.7,
                                       options: options)
        }
        #expect(throws: KernelError.self) {
            try evaluator.contactCurve(
                on: .first, fromCurveParameter: 0.7, toCurveParameter: 4,
                options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536,
                               maximumDeviation: tolerance.distance * 2)
            )
        }
        let unrelated = try RollingBallSectionEvaluator(
            first: sphere,
            second: OffsetSurface3D(
                source: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 1), normal: .unitZ)),
                distance: 0.2
            ), intersection: component, tolerance: tolerance
        )
        #expect(throws: KernelError.self) {
            try unrelated.contactCurve(on: .second, fromCurveParameter: 0.7, toCurveParameter: 4,
                                       options: options)
        }
    }

    @Test
    func blendSurfaceRetainsCircularSectionsMixedDerivativesAndEnclosures() throws {
        let sphere = OffsetSurface3D(
            source: .analytic(.sphere(center: .origin, radius: 2)), distance: -0.2
        )
        let plane = OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)), distance: 0.2
        )
        let evaluator: any RollingBallSectionEvaluating = try RollingBallSectionEvaluator(
            first: sphere, second: plane, intersection: intersection(sphere, plane), tolerance: tolerance
        )
        let surface = try evaluator.blendSurface(
            fromCurveParameter: 0.7, toCurveParameter: 4,
            options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536)
        )
        let encoded = try JSONEncoder().encode(surface)
        let fullSection = try surface.intervalJet(over: SurfaceParameterBox(
            u: ScalarInterval(lower: 0.2, upper: 0.2001), v: ScalarInterval(lower: 0, upper: 1)))
        for v in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let point = try surface.point(u: 0.20005, v: v)
            for (coordinate, bound) in [(point.x, fullSection.x.value),
                                        (point.y, fullSection.y.value), (point.z, fullSection.z.value)] {
                #expect(coordinate >= bound.lower && coordinate <= bound.upper)
            }
        }
        let restored = try JSONDecoder().decode(RollingBallBlendSurface3D.self, from: encoded)
        #expect(restored == surface)
        let native = Surface3D.procedural(.rollingBall(surface))
        let sectionLift = SurfaceLiftCurve3D(surface: native,
            parameterCurve: .constantU(u: 0.4, vStart: 0, vEnd: 1))
        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: .surfaceLift(sectionLift), from: 0, to: 1,
                surface: native, parameterCurve: .constantU(u: 0.6, vStart: 0, vEnd: 1),
                options: .init(maximumSubdivisionDepth: 4, maximumCellCount: 64),
                tolerance: tolerance)
        }
        for reversed in [false, true] {
            let lift = SurfaceLiftCurve3D(
                surface: native,
                parameterCurve: .constantU(u: 0.4, vStart: reversed ? 1 : 0,
                                          vEnd: reversed ? 0 : 1)
            )
            let converted = try AnalyticCurveBSplineBuilder().boundedCurve(
                curve: .surfaceLift(lift), interval: try ScalarInterval(lower: 0.2, upper: 0.8),
                maximumSpanCount: 1, tolerance: tolerance
            )
            let section = try #require(converted)
            for fraction in [0.2, 0.35, 0.5, 0.8] {
                let expected = try lift.point(atNormalizedFraction: fraction, tolerance: tolerance)
                let actual = try Curve3D.bSpline(section).point(at: fraction, tolerance: tolerance)
                #expect((actual - expected).length <= tolerance.distance)
            }
        }
        let restoredNative = try JSONDecoder().decode(
            Surface3D.self, from: JSONEncoder().encode(native)
        )
        #expect(restoredNative == native)
        let transform = try RigidTransform3D(
            basisX: .unitY, basisY: .unitZ, basisZ: .unitX,
            translation: Vector3D(x: 3, y: -2, z: 5), tolerance: tolerance
        )
        let moved = try transform.applying(to: restoredNative, tolerance: tolerance)
        var invalid = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        invalid["radius"] = -0.2
        let invalidRadius = try JSONSerialization.data(withJSONObject: invalid)
        #expect(throws: KernelError.self) {
            try JSONDecoder().decode(RollingBallBlendSurface3D.self, from: invalidRadius)
        }
        invalid["radius"] = 0.2
        invalid["certified"] = true
        let unknownField = try JSONSerialization.data(withJSONObject: invalid)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RollingBallBlendSurface3D.self, from: unknownField)
        }
        let span = 3.3
        let majorRadius = sqrt(1.8 * 1.8 - 0.04)
        for u in [0.0, 0.2, 0.5, 1.0] {
            let section = try evaluator.section(atCurveParameter: 0.7 + span * u)
            for v in [0.0, 0.3, 0.6, 1.0] {
                let point = try surface.point(u: u, v: v)
                let restoredPoint = try restored.point(u: u, v: v)
                #expect((point - restoredPoint).length <= tolerance.distance)
                let nativePoint = try restoredNative.point(u: u, v: v, tolerance: tolerance)
                #expect((nativePoint - point).length <= tolerance.distance)
                let movedPoint = try moved.point(u: u, v: v, tolerance: tolerance)
                #expect((movedPoint - transform.applying(to: point)).length <= tolerance.distance)
                let expected = try section.arc.point(at: v, tolerance: tolerance)
                #expect((point - expected).length <= tolerance.distance)
                let radial = hypot(point.x, point.y) - majorRadius
                #expect(abs(radial * radial + pow(point.z - 0.2, 2) - 0.04) <= tolerance.distance)
                let d = try surface.parameterDerivativesThroughThirdOrder(u: u, v: v)
                #expect((point - d.position).length <= tolerance.distance)
                let xy = Vector3D(x: point.x, y: point.y, z: 0)
                let expectedU = Vector3D.unitZ.cross(xy) * span
                #expect((d.tangentU - expectedU).length <= tolerance.distance)
                #expect((d.secondDerivativeUU + xy * (span * span)).length <= tolerance.distance)
                #expect((d.thirdDerivativeUUU + expectedU * (span * span)).length <= tolerance.distance)
                #expect((d.secondDerivativeUV - Vector3D.unitZ.cross(d.tangentV) * span).length <= tolerance.distance)
                #expect((d.thirdDerivativeUVV - Vector3D.unitZ.cross(d.secondDerivativeVV) * span).length <= tolerance.distance)
                let vXY = Vector3D(x: d.tangentV.x, y: d.tangentV.y, z: 0)
                #expect((d.thirdDerivativeUUV + vXY * (span * span)).length <= tolerance.distance)
                if v == 0 || v == 1 {
                    let normal = v == 0 ? (point - .origin) / 2 : .unitZ
                    #expect(abs(d.tangentV.dot(normal)) <= tolerance.distance)
                    #expect(abs(d.tangentU.dot(normal)) <= tolerance.distance)
                } else {
                    let h = 1.0e-5
                    let lower = try surface.parameterDerivatives(u: u, v: v - h)
                    let upper = try surface.parameterDerivatives(u: u, v: v + h)
                    let third = (upper.secondDerivativeVV - lower.secondDerivativeVV) / (2 * h)
                    #expect((third - d.thirdDerivativeVVV).length <= 1.0e-5)
                }
            }
        }
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0.2, upper: 0.201),
                                      v: try ScalarInterval(lower: 0.3, upper: 0.31))
        let enclosure = try surface.intervalJet(over: box)
        for u in [box.u.lower, box.u.midpoint, box.u.upper] {
            for v in [box.v.lower, box.v.midpoint, box.v.upper] {
                let d = try surface.parameterDerivativesThroughThirdOrder(u: u, v: v)
                for (value, bounds) in [
                    (d.position - .origin, [enclosure.x.value, enclosure.y.value, enclosure.z.value]),
                    (d.tangentU, [enclosure.x.derivativeU, enclosure.y.derivativeU, enclosure.z.derivativeU]),
                    (d.tangentV, [enclosure.x.derivativeV, enclosure.y.derivativeV, enclosure.z.derivativeV]),
                    (d.secondDerivativeUV, [enclosure.x.secondDerivativeUV, enclosure.y.secondDerivativeUV, enclosure.z.secondDerivativeUV]),
                    (d.thirdDerivativeUUU, [enclosure.x.thirdDerivativeUUU, enclosure.y.thirdDerivativeUUU, enclosure.z.thirdDerivativeUUU]),
                    (d.thirdDerivativeUUV, [enclosure.x.thirdDerivativeUUV, enclosure.y.thirdDerivativeUUV, enclosure.z.thirdDerivativeUUV]),
                    (d.thirdDerivativeUVV, [enclosure.x.thirdDerivativeUVV, enclosure.y.thirdDerivativeUVV, enclosure.z.thirdDerivativeUVV]),
                    (d.thirdDerivativeVVV, [enclosure.x.thirdDerivativeVVV, enclosure.y.thirdDerivativeVVV, enclosure.z.thirdDerivativeVVV])
                ] {
                    for (coordinate, bound) in zip([value.x, value.y, value.z], bounds) {
                        #expect(coordinate >= bound.lower && coordinate <= bound.upper)
                    }
                }
            }
        }
        #expect(throws: KernelError.self) { try surface.point(u: -0.1, v: 0.5) }
        #expect(throws: KernelError.self) { try surface.point(u: 0.5, v: .nan) }
        #expect(throws: KernelError.self) {
            try surface.intervalJet(over: SurfaceParameterBox(
                u: ScalarInterval(lower: 0.2, upper: 0.3), v: ScalarInterval(lower: -0.1, upper: 0.5)))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func helicalBlendRetainsRadiusAndBothSourceTangentPlanes() throws {
        // Independent analytic rails: a helicoid and its rolling-ball cylinder.
        // This exercises blend geometry, not intersection or solid reconstruction.
        let width = 2.0
        let pitch = 0.3
        let radius = 0.1
        let length = hypot(width, pitch)
        let centerRadius = hypot(width, radius * pitch / length)
        let phase = atan2(radius * pitch / length, width)
        let height = -radius * width / length
        func helix(_ radius: Double, phase: Double = 0, height: Double = 0) -> SurfaceLiftCurve3D {
            SurfaceLiftCurve3D(
                surface: .analytic(.cylinder(
                    origin: Point3D(x: 0, y: 0, z: height), axis: .unitZ, radius: radius
                )),
                parameterCurve: .affine(
                    origin: Point2D(x: 0.2 + phase, y: pitch * 0.2),
                    direction: Point2D(x: 1, y: pitch), startParameter: 0, endParameter: 1
                )
            )
        }
        let helicoid = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .surfaceLift(helix(width)),
            endBoundary: .surfaceLift(helix(width + 1))
        )))
        let first = helix(centerRadius - radius, phase: phase, height: height)
        let second = SurfaceLiftCurve3D(
            surface: helicoid, parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1)
        )
        let center = Curve3D.surfaceLift(helix(centerRadius, phase: phase, height: height))
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        try center.validate(tolerance: tolerance)
        let interval = try ScalarInterval(lower: 0.2, upper: 0.3)
        let encloser = DefaultCurveDifferentialEncloser()
        let liftedJet = try encloser.thirdOrderIntervalJet(
            of: .surfaceLift(second), over: interval, tolerance: tolerance
        )
        let boundaryJet = try encloser.thirdOrderIntervalJet(
            of: .surfaceLift(helix(width)), over: interval, tolerance: tolerance
        )
        for parameter in [interval.lower, interval.midpoint, interval.upper] {
            let derivative = try Curve3D.surfaceLift(helix(width))
                .parameterDerivativesThroughThirdOrder(at: parameter, tolerance: tolerance)
            for (vector, bounds) in [
                (derivative.firstDerivative, [boundaryJet.x.derivativeU, boundaryJet.y.derivativeU, boundaryJet.z.derivativeU]),
                (derivative.secondDerivative, [boundaryJet.x.secondDerivativeUU, boundaryJet.y.secondDerivativeUU, boundaryJet.z.secondDerivativeUU]),
                (derivative.thirdDerivative, [boundaryJet.x.thirdDerivativeUUU, boundaryJet.y.thirdDerivativeUUU, boundaryJet.z.thirdDerivativeUUU])
            ] {
                for (value, bound) in zip([vector.x, vector.y, vector.z], bounds) {
                    #expect(value >= bound.lower && value <= bound.upper)
                }
            }
        }
        for (actual, expected) in zip(
            [liftedJet.x, liftedJet.y, liftedJet.z], [boundaryJet.x, boundaryJet.y, boundaryJet.z]
        ) {
            for (a, b) in zip(
                [actual.value, actual.derivativeU, actual.secondDerivativeUU, actual.thirdDerivativeUUU],
                [expected.value, expected.derivativeU, expected.secondDerivativeUU, expected.thirdDerivativeUUU]
            ) {
                #expect(a.lower == b.lower && a.upper == b.upper)
            }
        }
        let blend = RollingBallBlendSurface3D(
            centerSpine: center, firstContact: .surfaceLift(first), secondContact: .surfaceLift(second),
            radius: radius, tolerance: tolerance
        )
        let box = SurfaceParameterBox(
            u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0, upper: 1)
        )
        try blend.validateRegularity(over: box, maximumSubdivisionDepth: 16, maximumCellCount: 65_536)
        #expect(throws: KernelError.self) {
            try blend.validateRegularity(over: box, maximumSubdivisionDepth: 1, maximumCellCount: 1)
        }
        for u in [0.0, 0.3, 0.7, 1.0] {
            let centerPoint = try center.point(at: u, tolerance: tolerance)
            for v in [0.0, 0.4, 1.0] {
                let value = try blend.parameterDerivativesThroughThirdOrder(u: u, v: v)
                #expect(abs((value.position - centerPoint).length - radius) <= tolerance.distance)
                if v == 0 || v == 1 {
                    let rail = v == 0 ? first : second
                    let contact = try rail.point(atNormalizedFraction: u, tolerance: tolerance)
                    #expect(value.position.isApproximatelyEqual(to: contact, tolerance: tolerance.distance))
                    let normal = try (centerPoint - contact).normalized(tolerance: tolerance.distance)
                    #expect(abs(value.tangentU.dot(normal)) <= tolerance.distance)
                    #expect(abs(value.tangentV.dot(normal)) <= tolerance.distance)
                }
            }
        }
    }

    @Test
    func invalidRadiusParametersAndUnrelatedCorrespondenceAreRejected() throws {
        let first = OffsetSurface3D(
            source: .analytic(.sphere(center: .origin, radius: 2)), distance: -0.2
        )
        let second = OffsetSurface3D(
            source: .plane(Plane3D(origin: .origin, normal: .unitZ)), distance: 0.2
        )
        let component = try intersection(first, second)
        for radius in [0.0, 0.1, Double.nan, Double.infinity] {
            #expect(throws: (any Error).self) {
                try RollingBallSectionEvaluator(
                    first: first,
                    second: OffsetSurface3D(source: second.source, distance: radius),
                    intersection: component, tolerance: tolerance
                )
            }
        }
        let evaluator = try RollingBallSectionEvaluator(
            first: first, second: second, intersection: component, tolerance: tolerance
        )
        #expect(throws: (any Error).self) {
            try evaluator.section(atCurveParameter: .nan)
        }
        let unrelated = try RollingBallSectionEvaluator(
            first: first,
            second: OffsetSurface3D(
                source: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 1), normal: .unitZ)),
                distance: 0.2
            ),
            intersection: component, tolerance: tolerance
        )
        #expect(throws: KernelError.self) {
            try unrelated.section(atCurveParameter: 0)
        }
    }

    @Test
    func coincidentAndAntipodalContactsAreRejected() throws {
        let source = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let first = OffsetSurface3D(source: source, distance: 0.2)
        let target = Surface3D.procedural(.offset(first))
        for opposite in [false, true] {
            let second = opposite
                ? OffsetSurface3D(
                    source: .plane(Plane3D(origin: Point3D(x: 0, y: 0, z: 0.4), normal: .unitZ)),
                    distance: -0.2
                ) : first
            let secondTarget = Surface3D.procedural(.offset(second))
            let result = try SurfaceSurfaceIntersectionVerifier().curve(
                .line(Line3D(origin: Point3D(x: 0, y: 0, z: 0.2), direction: .unitX)),
                kind: .transverse, firstSurface: target, secondSurface: secondTarget,
                sampleParameters: [-1, 0, 1], tolerance: tolerance
            )
            guard case let .curve(component) = result else {
                Issue.record("The coincident-surface fixture must carry a curve.")
                return
            }
            let evaluator = try RollingBallSectionEvaluator(
                first: first, second: second, intersection: component, tolerance: tolerance
            )
            #expect(throws: KernelError.self) {
                try evaluator.section(atCurveParameter: 0)
            }
        }
    }

    private func intersection(
        _ first: OffsetSurface3D, _ second: OffsetSurface3D
    ) throws -> SurfaceSurfaceIntersectionCurve {
        let results = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(first)), second: .procedural(.offset(second)),
            tolerance: tolerance
        )
        #expect(results.count == 1)
        let result = try #require(results.first)
        guard case let .curve(component) = result else {
            throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                              message: "The contact fixture must have a transverse curve.")
        }
        return component
    }
}
