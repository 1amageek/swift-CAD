import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

@Suite("Exact curved revolve")
struct CurvedRevolveFeatureTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func circularProfileProducesDeterministicTrimmedRationalSurfaces() throws {
        let profileFeatureID = FeatureID()
        let revolveFeatureID = FeatureID()
        let profile = circularProfile(featureID: profileFeatureID)
        let feature = revolveFeature(
            id: revolveFeatureID,
            profileFeatureID: profileFeatureID,
            angleDegrees: 180.0
        )
        let context = evaluationContext(
            profileFeatureID: profileFeatureID,
            profile: profile
        )

        let result = try PlanarRevolveFeatureEvaluator().evaluate(
            feature: feature,
            context: context
        )
        let repeated = try PlanarRevolveFeatureEvaluator().evaluate(
            feature: feature,
            context: context
        )

        #expect(result.brep == repeated.brep)
        #expect(result.lineage == repeated.lineage)
        #expect(result.brep.faces.count == 10)
        #expect(result.brep.geometry.surfaces.values.filter {
            if case .bSpline = $0 { return true }
            return false
        }.count == 8)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)

        for surface in result.brep.geometry.surfaces.values {
            guard case let .bSpline(value) = surface,
                  case let .closed(uLower, uUpper) = value.uDomain,
                  case let .closed(vLower, vUpper) = value.vDomain else {
                continue
            }
            let point = try value.point(
                u: uLower + 0.37 * (uUpper - uLower),
                v: vLower + 0.41 * (vUpper - vLower),
                tolerance: tolerance
            )
            let radial = hypot(point.x, point.z)
            let torusResidual = abs(hypot(radial - 0.03, point.y) - 0.01)
            #expect(torusResidual <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cubicSplineBoundaryRemainsExactThroughFullRevolution() throws {
        let profileFeatureID = FeatureID()
        let revolveFeatureID = FeatureID()
        let profile = try splineProfile(featureID: profileFeatureID)
        let feature = revolveFeature(
            id: revolveFeatureID,
            profileFeatureID: profileFeatureID,
            angleDegrees: 360.0
        )
        let result = try PlanarRevolveFeatureEvaluator().evaluate(
            feature: feature,
            context: evaluationContext(
                profileFeatureID: profileFeatureID,
                profile: profile
            )
        )

        #expect(result.brep.faces.count == 8)
        #expect(result.brep.geometry.surfaces.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)

        let sourceCurve: BSplineCurve3D
        guard case let .spline(spline) = profile.boundarySegments[0] else {
            Issue.record("Expected an exact spline profile segment.")
            return
        }
        sourceCurve = spline.curve
        let sourcePoint = try sourceCurve.point(at: 0.5, tolerance: tolerance)
        let curvedSurface = try #require(result.brep.geometry.surfaces.values.first {
            guard case let .bSpline(surface) = $0 else { return false }
            return surface.vDegree == 3
        })
        guard case let .bSpline(surface) = curvedSurface,
              case let .closed(uLower, uUpper) = surface.uDomain else {
            Issue.record("Expected a rational spline surface of revolution.")
            return
        }
        let revolvedPoint = try surface.point(
            u: 0.5 * (uLower + uUpper),
            v: 0.5,
            tolerance: tolerance
        )
        #expect(abs(hypot(revolvedPoint.x, revolvedPoint.z) - sourcePoint.x)
            <= tolerance.distance)
        #expect(abs(revolvedPoint.y - sourcePoint.y) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func axisBoundedSemicircleUsesCollapsedBoundaryTopology() throws {
        let profileFeatureID = FeatureID()
        let radius = 0.02
        let lower = Point3D(x: 0.0, y: -radius, z: 0.0)
        let upper = Point3D(x: 0.0, y: radius, z: 0.0)
        let profile = Profile(
            sourceFeatureID: profileFeatureID,
            plane: .xy,
            vertices: [
                lower,
                Point3D(x: radius, y: 0.0, z: 0.0),
                upper,
            ],
            boundarySegments: [
                .circularArc(ProfileCircularArcSegment(
                    center: .origin,
                    normal: .unitZ,
                    radius: radius,
                    start: lower,
                    end: upper,
                    sweepAngle: Double.pi
                )),
                .line(ProfileLineSegment(start: upper, end: lower)),
            ]
        )
        let result = try PlanarRevolveFeatureEvaluator().evaluate(
            feature: revolveFeature(
                id: FeatureID(),
                profileFeatureID: profileFeatureID,
                angleDegrees: 360.0
            ),
            context: evaluationContext(
                profileFeatureID: profileFeatureID,
                profile: profile
            )
        )

        #expect(result.brep.faces.count == 8)
        #expect(result.brep.loops.values.allSatisfy { $0.coedges.count == 3 })
        try result.brep.validate(level: .exact, tolerance: tolerance)
        for surface in result.brep.geometry.surfaces.values {
            guard case let .bSpline(value) = surface,
                  case let .closed(uLower, uUpper) = value.uDomain,
                  case let .closed(vLower, vUpper) = value.vDomain else {
                continue
            }
            let point = try value.point(
                u: uLower + 0.43 * (uUpper - uLower),
                v: vLower + 0.39 * (vUpper - vLower),
                tolerance: tolerance
            )
            #expect(abs((point - Point3D.origin).length - radius)
                <= tolerance.distance)
        }
    }

    private func circularProfile(featureID: FeatureID) -> Profile {
        let center = Point3D(x: 0.03, y: 0.0, z: 0.0)
        let start = Point3D(x: 0.04, y: 0.0, z: 0.0)
        return Profile(
            sourceFeatureID: featureID,
            plane: .xy,
            vertices: [
                start,
                Point3D(x: 0.03, y: 0.01, z: 0.0),
                Point3D(x: 0.02, y: 0.0, z: 0.0),
                Point3D(x: 0.03, y: -0.01, z: 0.0),
            ],
            boundarySegments: [.circularArc(ProfileCircularArcSegment(
                center: center,
                normal: .unitZ,
                radius: 0.01,
                start: start,
                end: start,
                sweepAngle: 2.0 * Double.pi
            ))]
        )
    }

    private func splineProfile(featureID: FeatureID) throws -> Profile {
        let curve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.01, y: 0.0, z: 0.0),
                Point3D(x: 0.02, y: 0.005, z: 0.0),
                Point3D(x: 0.02, y: 0.015, z: 0.0),
                Point3D(x: 0.01, y: 0.02, z: 0.0),
            ]
        )
        try curve.validate(tolerance: tolerance)
        let samples = try (0...8).map { index in
            try curve.point(
                at: Double(index) / 8.0,
                tolerance: tolerance
            )
        }
        return Profile(
            sourceFeatureID: featureID,
            plane: .xy,
            vertices: samples,
            boundarySegments: [
                .spline(ProfileSplineSegment(curve: curve)),
                .line(ProfileLineSegment(
                    start: try #require(samples.last),
                    end: try #require(samples.first)
                )),
            ]
        )
    }

    private func revolveFeature(
        id: FeatureID,
        profileFeatureID: FeatureID,
        angleDegrees: Double
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            operation: .revolve(RevolveFeature(
                profile: ProfileReference(featureID: profileFeatureID),
                axis: RevolveAxis(origin: .origin, direction: .unitY),
                angle: .constant(.angle(angleDegrees, unit: .degree))
            )),
            inputs: [FeatureInput(featureID: profileFeatureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
    }

    private func evaluationContext(
        profileFeatureID: FeatureID,
        profile: Profile
    ) -> EvaluationContext {
        EvaluationContext(
            parameters: ResolvedParameterTable(),
            brep: BRepModel(),
            profiles: [profileFeatureID: [profile]],
            tolerance: tolerance
        )
    }
}
