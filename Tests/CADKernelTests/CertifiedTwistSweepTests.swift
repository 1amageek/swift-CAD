import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel

@Suite("Certified twist Sweep")
struct CertifiedTwistSweepTests {
    private let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)

    @Test(.timeLimit(.minutes(1)))
    func rationalProfileCertificateAndArtificialSeams() throws {
        let fixture = try fixture(doubleHelical: false)
        let plan = try CertifiedTwistSweepPlan(profile: fixture.profile,
            pathSegments: [EvaluatedCurvePathSegment(curve: fixture.path)], sweep: fixture.sweep,
            values: fixture.values, tolerance: tolerance)
        #expect(plan.positionErrorUpperBound > 0)
        #expect(plan.positionErrorUpperBound <= 1e-6)
        #expect(plan.pathSpans.count > 1)
        let surfaces = plan.surfaces[0].map { $0[0] }
        for (index, surface) in surfaces.enumerated() {
            #expect(surface.uDegree == fixture.profileCurve.degree)
            #expect(surface.vDegree == 3)
            #expect(surface.weights.allSatisfy { $0 == fixture.profileCurve.weights })
            let lower = plan.pathSpans[index].startPoint.z / 0.05
            let upper = plan.pathSpans[index].endPoint.z / 0.05
            for u in [0.0, 0.21, 0.63, 1.0] {
                let p = try fixture.profileCurve.point(at: u, tolerance: tolerance)
                for v in [0.0, 0.19, 0.5, 0.81, 1.0] {
                    let s = lower + (upper - lower) * v
                    let a = s * 0.8
                    let expected = Point3D(x: p.x * cos(a) - p.y * sin(a),
                        y: p.x * sin(a) + p.y * cos(a), z: 0.05 * s)
                    let actual = try surface.point(u: u, v: v, tolerance: tolerance)
                    #expect((actual - expected).length <= plan.positionErrorUpperBound + 1e-14)
                }
            }
            if index > 0 {
                let previous = surfaces[index - 1]
                let previousWidth = plan.pathSpans[index - 1].endPoint.z - plan.pathSpans[index - 1].startPoint.z
                let width = plan.pathSpans[index].endPoint.z - plan.pathSpans[index].startPoint.z
                for i in surface.controlPoints[0].indices {
                    let leftPoint = previous.controlPoints[3][i]
                    let rightPoint = surface.controlPoints[0][i]
                    let leftDerivative = (leftPoint - previous.controlPoints[2][i]) * (3 / previousWidth)
                    let rightDerivative = (surface.controlPoints[1][i] - rightPoint) * (3 / width)
                    #expect((leftPoint - rightPoint).length < 1e-13)
                    #expect((leftDerivative - rightDerivative).length < 1e-10)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func doubleHelicalSolidHasOnlyExteriorCapsAndTessellates() throws {
        let fixture = try fixture(doubleHelical: true)
        let featureID = FeatureID()
        let feature = FeatureNode(id: featureID, operation: .sweep(fixture.sweep))
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [fixture.profile.sourceFeatureID: [fixture.profile]],
            curves: [fixture.path.sourceFeatureID: [fixture.path]], tolerance: tolerance)
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(feature: feature, context: context)
        #expect(result.brep.bodies.count == 1)
        #expect(result.brep.shells.count == 1)
        #expect(result.brep.geometry.surfaces.values.filter {
            if case .plane = $0 { return true }; return false
        }.count == 2)
        #expect(result.brep.loops.values.allSatisfy { $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil } })
        try result.brep.validate(level: .exact, tolerance: tolerance)
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(model: result.brep)
        #expect(meshes.count == 1)
        for mesh in meshes.values { try mesh.validate(tolerance: tolerance) }
        let plan = try CertifiedTwistSweepPlan(profile: fixture.profile,
            pathSegments: [EvaluatedCurvePathSegment(curve: fixture.path)], sweep: fixture.sweep,
            values: fixture.values, tolerance: tolerance)
        let middle = try #require(plan.pathSpans.firstIndex { abs($0.endPoint.z - 0.025) < 1e-12 })
        let left = plan.surfaces[0][middle][0]
        let right = plan.surfaces[0][middle + 1][0]
        let dl = left.controlPoints[3][1] - left.controlPoints[2][1]
        let dr = right.controlPoints[1][1] - right.controlPoints[0][1]
        #expect(dl.x * dr.x + dl.y * dr.y < 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func multiToothConstructionProfileProducesOneDoubleHelicalSolid() throws {
        // Construction fixture only: these trapezoidal teeth are not an involute
        // profile and provide no manufacturing, meshing or gear-accuracy claim.
        let fixture = try fixture(doubleHelical: true)
        let toothCount = 8
        let pitch = 2 * Double.pi / Double(toothCount)
        let vertices = (0..<(4 * toothCount)).map { index in
            let radius = index % 4 == 1 || index % 4 == 2 ? 0.028 : 0.020
            let angle = Double(index) * pitch / 4
            return Point3D(x: radius * cos(angle), y: radius * sin(angle), z: 0)
        }
        let profile = Profile(sourceFeatureID: fixture.profile.sourceFeatureID, plane: .xy,
            vertices: vertices, boundarySegments: vertices.indices.map { index in
                .line(ProfileLineSegment(start: vertices[index], end: vertices[(index + 1) % vertices.count]))
            })
        var sweep = fixture.sweep
        sweep.options.twistLaw?[1].angle = .constant(.angle(0.12, unit: .radian))
        let values = try SweepOptionValueResolver().values(for: sweep,
            parameters: ResolvedParameterTable(), tolerance: tolerance)
        let plan = try CertifiedTwistSweepPlan(profile: profile,
            pathSegments: [EvaluatedCurvePathSegment(curve: fixture.path)], sweep: sweep,
            values: values, tolerance: tolerance)
        #expect(plan.profileSpanLoops[0].count == 4 * toothCount)
        #expect(plan.positionErrorUpperBound <= 1e-6)
        let feature = FeatureNode(operation: .sweep(sweep))
        let context = EvaluationContext(parameters: ResolvedParameterTable(), brep: BRepModel(),
            profiles: [profile.sourceFeatureID: [profile]],
            curves: [fixture.path.sourceFeatureID: [fixture.path]], tolerance: tolerance)
        let result = try PlanarSweepFeatureEvaluator(sewer: DefaultBRepSewer()).evaluate(feature: feature, context: context)
        let body = try #require(result.brep.bodies.values.first)
        #expect(result.brep.bodies.count == 1)
        #expect(body.kind == .solid)
        #expect(body.solidComponents?.count == 1)
        #expect(result.brep.shells.count == 1)
        #expect(result.brep.faces.count == 4 * toothCount * plan.pathSpans.count + 2)
        #expect(result.brep.geometry.surfaces.values.filter {
            if case .plane = $0 { return true }; return false
        }.count == 2)
        try result.brep.validate(level: .exact, tolerance: tolerance)
        // Compare the actual sewn surfaces with the retained construction profile,
        // independently of the plan's tensor coefficients.
        var coveredEdges = Set<Int>()
        for geometry in result.brep.geometry.surfaces.values {
            guard case let .bSpline(surface) = geometry else { continue }
            for u in [0.21, 0.5, 0.79] {
                for v in [0.19, 0.5, 0.81] {
                    let point = try surface.point(u: u, v: v, tolerance: tolerance)
                    let position = point.z / 0.05
                    let angle = 0.12 * (position <= 0.5 ? 2 * position : 2 * (1 - position))
                    let original = Point3D(x: point.x * cos(angle) + point.y * sin(angle),
                        y: -point.x * sin(angle) + point.y * cos(angle), z: 0)
                    var nearestDistance = Double.infinity
                    var nearestEdge = 0
                    for index in vertices.indices {
                        let edge = vertices[(index + 1) % vertices.count] - vertices[index]
                        let fraction = min(1, max(0, (original - vertices[index]).dot(edge) / edge.dot(edge)))
                        let distance = (original - (vertices[index] + edge * fraction)).length
                        if distance < nearestDistance {
                            nearestDistance = distance
                            nearestEdge = index
                        }
                    }
                    #expect(nearestDistance <= plan.positionErrorUpperBound + 1e-14)
                    coveredEdges.insert(nearestEdge)
                }
            }
        }
        #expect(coveredEdges.count == vertices.count)
        let meshes = try MeshTessellator(tolerance: tolerance).tessellate(model: result.brep)
        #expect(meshes.count == 1)
        for mesh in meshes.values { try mesh.validate(tolerance: tolerance) }
    }

    @Test(.timeLimit(.minutes(1)))
    func refusesMissingAllowanceScaleCurvatureAndUnattainableError() throws {
        let fixture = try fixture(doubleHelical: false)
        for mode in 0..<4 {
            var values = fixture.values
            var path = fixture.path
            if mode == 0 { values.approximationTolerance = nil }
            if mode == 1 { values.endScale = 0.9 }
            if mode == 2 {
                path.exactCurve = .bSpline(BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
                    controlPoints: [.origin, Point3D(x: 0.001, y: 0, z: 0.025), Point3D(x: 0, y: 0, z: 0.05)]))
            }
            if mode == 3 { values.approximationTolerance = 1e-30 }
            #expect(throws: KernelError.self) {
                _ = try CertifiedTwistSweepPlan(profile: fixture.profile,
                    pathSegments: [EvaluatedCurvePathSegment(curve: path)], sweep: fixture.sweep,
                    values: values, tolerance: tolerance)
            }
        }
    }

    private func fixture(doubleHelical: Bool) throws -> (
        profile: Profile, profileCurve: BSplineCurve3D, path: EvaluatedCurve,
        sweep: SweepFeature, values: SweepOptionValues
    ) {
        let profileID = FeatureID()
        let pathID = FeatureID()
        let curve = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: [.origin, Point3D(x: 0.02, y: 0.004, z: 0),
                Point3D(x: 0.018, y: 0.016, z: 0), Point3D(x: 0, y: 0.02, z: 0)],
            weights: [1, 0.8, 1.2, 1])
        let samples = try (0...8).map { try curve.point(at: Double($0) / 8, tolerance: tolerance) }
        let profile = Profile(sourceFeatureID: profileID, plane: .xy, vertices: samples,
            boundarySegments: [.spline(ProfileSplineSegment(curve: curve)),
                .line(ProfileLineSegment(start: samples[8], end: samples[0]))])
        let pathCurve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, Point3D(x: 0, y: 0, z: 0.05)])
        let path = EvaluatedCurve(sourceFeatureID: pathID, source: .generatedFeature, kind: .spline,
            points: pathCurve.controlPoints, plane: .yz, exactCurve: .bSpline(pathCurve), exactParameterDomain: pathCurve.domain)
        let endAngle = doubleHelical ? 0.0 : 0.8
        let law: [SweepTwistKnot]? = doubleHelical ? [
            SweepTwistKnot(position: 0, angle: .constant(.angle(0, unit: .radian))),
            SweepTwistKnot(position: 0.5, angle: .constant(.angle(0.4, unit: .radian))),
            SweepTwistKnot(position: 1, angle: .constant(.angle(0, unit: .radian)))
        ] : nil
        let sweep = SweepFeature(sections: [.profile(ProfileReference(featureID: profileID))],
            path: SweepPathReference(featureID: pathID),
            options: SweepOptions(twistAngle: .constant(.angle(endAngle, unit: .radian)),
                approximationTolerance: .constant(.length(1e-6, unit: .meter)), twistLaw: law))
        let values = try SweepOptionValueResolver().values(for: sweep, parameters: ResolvedParameterTable(), tolerance: tolerance)
        return (profile, curve, path, sweep, values)
    }
}
