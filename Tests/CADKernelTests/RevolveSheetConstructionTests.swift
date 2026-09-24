import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel
@testable import CADModeling

@Suite("Exact open-generator revolution", .timeLimit(.minutes(1)))
struct RevolveSheetConstructionTests {
    @Test(arguments: [Double.pi, -Double.pi, 2 * Double.pi], [false, true])
    func openGeneratorProducesUncappedSheet(angle: Double, rational: Bool) throws {
        let curve = rational
            ? BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.025, y: 0.01, z: 0),
                    Point3D(x: 0.03, y: 0.03, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)],
                weights: [1, 0.8, 1.2, 1])
            : BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)])
        let section = try section(curve)
        let result = try build(section, angle: angle)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == (abs(angle) > Double.pi ? 4 : 2))
        #expect(result.subshapes.keys.allSatisfy {
            $0.role != GeneratedSubshapeRole.startFace.rawValue && $0.role != GeneratedSubshapeRole.endFace.rawValue
        })
        for geometry in result.brep.geometry.surfaces.values {
            guard case .bSpline(let surface) = geometry else {
                Issue.record("Expected an exact rational rotation surface.")
                continue
            }
            for v in [0.15, 0.5, 0.85] {
                let original = try curve.point(at: v, tolerance: .standard)
                let rotated = try surface.point(u: 0.37, v: v, tolerance: .standard)
                #expect(abs(hypot(rotated.x, rotated.z) - original.x) < 1e-8)
                #expect(abs(rotated.y - original.y) < 1e-8)
            }
        }
    }

    @Test func axisCrossingAndInvalidAnglesAreRejected() throws {
        let crossing = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: -0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)]))
        #expect(throws: (any Error).self) { try build(crossing, angle: .pi) }
        let valid = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)]))
        for angle in [0, Double.infinity, Double.nan, 3 * Double.pi] {
            #expect(throws: (any Error).self) { try build(valid, angle: angle) }
        }
    }

    @Test(arguments: [Double.pi, -Double.pi, 2 * Double.pi], [false, true])
    func spatialGeneratorRevolvesWithoutInventingPlane(angle: Double, rational: Bool) throws {
        let curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.025, y: 0.01, z: 0.006),
                Point3D(x: 0.03, y: 0.03, z: -0.004), Point3D(x: 0.02, y: 0.04, z: 0.003)],
            weights: rational ? [1, 0.8, 1.2, 1] : nil)
        var input = try section(curve)
        input.plane = nil
        let feature = FeatureNode(operation: .revolve(RevolveFeature(
            section: .curve(CurveSectionReference(featureID: input.sourceFeatureID)),
            axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: .constant(.angle(angle, unit: .radian)), resultKind: .sheet)),
            inputs: [FeatureInput(featureID: input.sourceFeatureID, role: .curve)], outputs: [FeatureOutput(role: .sheet)])
        let result = try PlanarRevolveFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(feature: feature,
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(), profiles: [:],
                curves: [input.sourceFeatureID: [input]], tolerance: .standard))
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == (abs(angle) > .pi ? 4 : 2))
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        for surface in result.brep.geometry.surfaces.values {
            for u in [0.0, 0.5, 1.0] {
                let start = try surface.point(u: u, v: 0, tolerance: .standard)
                let rotation = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
                    angle: -atan2(start.z, start.x), tolerance: .standard)
                for v in [0.17, 0.5, 0.83, 1.0] {
                    let expected = rotation.applying(to: try curve.point(at: v, tolerance: .standard))
                    #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
                }
            }
        }
    }

    @Test(arguments: [Double.pi, -Double.pi, 2 * Double.pi], [false, true])
    func radialOrderingAdmitsAxiallyReversingSpatialGenerators(angle: Double, rational: Bool) throws {
        var curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.03, y: 0.01, z: 0.003),
                Point3D(x: 0.04, y: -0.01, z: 0.006), Point3D(x: 0.05, y: 0, z: 0.01)],
            weights: rational ? [1, 0.8, 1.2, 1] : nil)
        if angle < 0 { curve = try curve.reversed(tolerance: .standard) }
        let sourceStart = try curve.point(at: 0, tolerance: .standard)
        var input = try section(curve)
        input.plane = nil
        let result = try build(input, angle: angle)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.bodies.values.allSatisfy { $0.kind == .sheet })
        #expect(result.brep.faces.count == (abs(angle) > .pi ? 4 : 2))
        for surface in result.brep.geometry.surfaces.values {
            for u in [0.0, 0.5, 1.0] {
                let start = try surface.point(u: u, v: 0, tolerance: .standard)
                let rotation = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
                    angle: atan2(sourceStart.z, sourceStart.x) - atan2(start.z, start.x), tolerance: .standard)
                for v in [0.17, 0.5, 0.83, 1.0] {
                    let expected = rotation.applying(to: try curve.point(at: v, tolerance: .standard))
                    #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
                }
            }
        }
    }

    @Test func spatialAxisCrossingAndRepeatedOrbitsDoNotPublish() throws {
        for points in [
            [Point3D(x: -0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)],
            [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.025, y: 0.1, z: 0.01),
             Point3D(x: 0.03, y: -0.1, z: 0), Point3D(x: 0.02, y: 0.04, z: 0.01)],
            // Both ends generate the same orbit; the midpoint reverses radial traversal.
            [Point3D(x: 0.02, y: 0, z: -0.01), Point3D(x: 0.02, y: 0, z: 0.01)]
        ] {
            let degree = points.count - 1
            var input = try section(BSplineCurve3D(degree: degree,
                knots: Array(repeating: 0, count: degree + 1) + Array(repeating: 1, count: degree + 1),
                controlPoints: points))
            input.plane = nil
            #expect(throws: (any Error).self) { try build(input, angle: .pi) }
        }
    }

    @Test(arguments: [Double.pi, -Double.pi, 2 * Double.pi])
    func closedOffsetCircleHasDisjointRotationOrbits(angle: Double) throws {
        let curve = Curve3D.circle(Circle3D(center: Point3D(x: 0.03, y: 0, z: 0.004),
            normal: .unitZ, radius: 0.01))
        let parameters = [0.0, Double.pi / 2, Double.pi, 1.5 * Double.pi, 2 * Double.pi]
        let input = EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: try parameters.map { try curve.point(at: $0, tolerance: .standard) },
            isClosed: true, exactCurve: curve, exactParameterDomain: .closed(0, 2 * Double.pi),
            exactPointParameters: parameters)
        let result = try build(input, angle: angle)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == (abs(angle) > .pi ? 16 : 8))
        for surface in result.brep.geometry.surfaces.values {
            for u in [0.0, 0.3, 0.7, 1.0] {
                for v in [0.0, 0.3, 0.7, 1.0] {
                    let point = try surface.point(u: u, v: v, tolerance: .standard)
                    let sourceX = sqrt(point.x * point.x + point.z * point.z - 0.004 * 0.004)
                    #expect(abs((sourceX - 0.03) * (sourceX - 0.03) + point.y * point.y - 0.0001) < 1e-10)
                }
            }
        }
    }

    @Test func nonmonotoneSpatialGeneratorProducesExactRegularSheet() throws {
        let curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.08, y: 0.01, z: 0.01),
                Point3D(x: 0.001, y: -0.01, z: 0.002), Point3D(x: 0.04, y: 0, z: 0.003)])
        var input = try section(curve)
        input.plane = nil
        let result = try build(input, angle: .pi)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 2)
        for surface in result.brep.geometry.surfaces.values {
            for u in [0.0, 0.3, 0.7, 1.0] {
                let start = try surface.point(u: u, v: 0, tolerance: .standard)
                let rotation = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
                    angle: -atan2(start.z, start.x), tolerance: .standard)
                for v in [0.0, 0.17, 0.5, 0.83, 1.0] {
                    let expected = rotation.applying(to: try curve.point(at: v, tolerance: .standard))
                    #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
                }
            }
        }
    }

    @Test(arguments: [0.1, -0.1, 0.5, -0.5], [0.0, 3.4])
    func repeatedOrbitsRequireDisjointSweptAngularIntervals(angle: Double, phase: Double) throws {
        let placement = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
            angle: phase, tolerance: .standard)
        let curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.025, y: 0.1, z: 0.01),
                Point3D(x: 0.03, y: -0.1, z: 0), Point3D(x: 0.02, y: 0.04, z: 0.01)]
                .map { placement.applying(to: $0) })
        var input = try section(curve)
        input.plane = nil
        if abs(angle) > 0.1 {
            #expect(throws: KernelError.self) { try build(input, angle: angle) }
            return
        }
        let result = try build(input, angle: angle)
        try result.brep.validate(level: .exact, tolerance: .standard)
        #expect(result.brep.faces.count == 1)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        for u in [0.0, 0.5, 1.0] {
            let rotation = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
                angle: angle * u, tolerance: .standard)
            for v in [0.0, 0.17, 0.5, 0.83, 1.0] {
                let expected = rotation.applying(to: try curve.point(at: v, tolerance: .standard))
                #expect((try surface.point(u: u, v: v, tolerance: .standard) - expected).length < 1e-8)
            }
        }
    }

    @Test func planarCurveCanRotateAroundAxisOutsideItsPlane() throws {
        let input = try section(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.02, y: 0.04, z: 0)]))
        let axis = RevolveAxis(origin: Point3D(x: 0, y: 0, z: 0.01), direction: .unitY)
        let result = try CurvedRevolveBodyBuilder.buildSheet(axis: axis, angle: .pi / 2,
            section: input, featureID: FeatureID(),
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], tolerance: .standard), sewer: DefaultBRepSewer())
        try result.brep.validate(level: .exact, tolerance: .standard)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        let rotation = try RigidTransform3D.rotated(around: axis.origin, direction: .unitY,
            angle: .pi / 4, tolerance: .standard)
        let expected = rotation.applying(to: Point3D(x: 0.02, y: 0.02, z: 0))
        #expect((try surface.point(u: 0.5, v: 0.5, tolerance: .standard) - expected).length < 1e-8)
    }

    @Test func offsetObliqueAxisPreservesRationalGeometryAndBoundaries() throws {
        let placement = try RigidTransform3D.rotated(around: Point3D(x: 0.2, y: -0.1, z: 0.3),
            direction: Vector3D(x: 1, y: 2, z: 3), angle: 0.7, tolerance: .standard)
        let curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0.02, y: 0, z: 0), Point3D(x: 0.03, y: 0.02, z: 0),
                Point3D(x: 0.02, y: 0.04, z: 0)], weights: [1, 0.7, 1])
        let placed = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
            controlPoints: curve.controlPoints.map { placement.applying(to: $0) }, weights: curve.weights)
        var input = try section(placed)
        let origin = placement.applying(to: Point3D.origin)
        input.plane = .plane(Plane3D(origin: origin, normal: placement.applying(to: Vector3D.unitZ)))
        let result = try CurvedRevolveBodyBuilder.buildSheet(
            axis: RevolveAxis(origin: origin, direction: placement.applying(to: Vector3D.unitY)),
            angle: .pi / 2, section: input, featureID: FeatureID(),
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], tolerance: .standard), sewer: DefaultBRepSewer())
        try result.brep.validate(level: .exact, tolerance: .standard)
        let surface = try #require(result.brep.geometry.surfaces.values.first)
        for (u, angle) in [(0.0, 0.0), (0.5, Double.pi / 4), (1.0, Double.pi / 2)] {
            let rotation = try RigidTransform3D.rotated(around: .origin, direction: .unitY,
                angle: angle, tolerance: .standard)
            for v in [0.0, 0.27, 0.8, 1.0] {
                let expected = placement.applying(to: rotation.applying(to: try curve.point(at: v, tolerance: .standard)))
                let actual = try surface.point(u: u, v: v, tolerance: .standard)
                #expect((actual - expected).length < 1e-8)
            }
        }
    }

    private func section(_ curve: BSplineCurve3D) throws -> EvaluatedCurve {
        EvaluatedCurve(sourceFeatureID: FeatureID(), source: .generatedFeature, kind: .spline,
            points: [try curve.point(at: 0, tolerance: .standard), try curve.point(at: 1, tolerance: .standard)],
            plane: .xy, exactCurve: .bSpline(curve), exactParameterDomain: .closed(0, 1),
            exactPointParameters: [0, 1])
    }

    private func build(_ section: EvaluatedCurve, angle: Double) throws -> EvaluationResult {
        try CurvedRevolveBodyBuilder.buildSheet(axis: RevolveAxis(origin: .origin, direction: .unitY),
            angle: angle, section: section, featureID: FeatureID(),
            context: EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
                profiles: [:], tolerance: .standard), sewer: DefaultBRepSewer())
    }
}
