import CADCore
import Foundation
import Testing
@testable import CADGeometry

@Suite("Rolling-ball contact sections", .timeLimit(.minutes(1)))
struct RollingBallSectionTests {
    private let tolerance = ModelingTolerance.standard

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
