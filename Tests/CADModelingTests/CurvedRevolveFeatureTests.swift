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
        }.count == 10)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)
        let volumetric = try ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .volumetric
        )
        let expectedVolume = Double.pi * Double.pi * 0.03 * 0.01 * 0.01
        #expect(abs(try #require(volumetric.volume) - expectedVolume)
            <= tolerance.distance * 0.05 * 0.05)

        for surface in result.brep.geometry.surfaces.values {
            guard case let .bSpline(value) = surface,
                  value.uDegree == 2,
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
    func rationalCubicSplineBoundaryRemainsExactThroughFullRevolution() throws {
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
        let volumetric = try ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .volumetric
        )
        #expect(try #require(volumetric.volume) > 0.0)

        let sourceCurve: BSplineCurve3D
        guard case let .spline(spline) = profile.boundarySegments[0] else {
            Issue.record("Expected an exact spline profile segment.")
            return
        }
        sourceCurve = spline.curve
        #expect(sourceCurve.isRational)
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
        #expect(surface.isRational)
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
    func multiSpanRationalBSplineBoundaryIsSplitWithoutLosingExactness() throws {
        let profileFeatureID = FeatureID()
        let profile = try multiSpanSplineProfile(featureID: profileFeatureID)
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

        #expect(result.brep.faces.count == 12)
        #expect(result.brep.geometry.surfaces.values.allSatisfy {
            if case .bSpline = $0 { return true }
            return false
        })
        #expect(result.brep.geometry.surfaces.values.filter {
            guard case let .bSpline(surface) = $0 else { return false }
            return surface.vDegree == 3 && surface.isRational
        }.count == 8)
        #expect(result.brep.loops.values.allSatisfy {
            $0.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        })
        try result.brep.validate(level: .exact, tolerance: tolerance)
        let volume = try #require(ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .volumetric
        ).volume)
        #expect(volume > 0.0)
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
        let volumetric = try ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .volumetric
        )
        let expectedVolume = 4.0 * Double.pi * radius * radius * radius / 3.0
        #expect(abs(try #require(volumetric.volume) - expectedVolume)
            <= tolerance.distance * 0.05 * 0.05)
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

    @Test(.timeLimit(.minutes(1)))
    func negativePartialAngleProducesValidatedExactVolume() throws {
        let profileFeatureID = FeatureID()
        let profile = circularProfile(featureID: profileFeatureID)
        let result = try PlanarRevolveFeatureEvaluator().evaluate(
            feature: revolveFeature(
                id: FeatureID(),
                profileFeatureID: profileFeatureID,
                angleDegrees: -180.0
            ),
            context: evaluationContext(
                profileFeatureID: profileFeatureID,
                profile: profile
            )
        )

        try result.brep.validate(level: .exact, tolerance: tolerance)
        let volume = try #require(ValidatedBRepModel(
            result.brep,
            tolerance: tolerance,
            validationLevel: .volumetric
        ).volume)
        let expectedVolume = Double.pi * Double.pi * 0.03 * 0.01 * 0.01
        #expect(abs(volume - expectedVolume)
            <= tolerance.distance * 0.05 * 0.05)
    }

    @Test
    func invalidAnglesReturnFeatureScopedKernelDiagnostics() throws {
        let profileFeatureID = FeatureID()
        let profile = circularProfile(featureID: profileFeatureID)
        let context = evaluationContext(
            profileFeatureID: profileFeatureID,
            profile: profile
        )
        let zeroFeatureID = FeatureID()
        do {
            _ = try PlanarRevolveFeatureEvaluator().evaluate(
                feature: revolveFeature(
                    id: zeroFeatureID,
                    profileFeatureID: profileFeatureID,
                    angleDegrees: 0.0
                ),
                context: context
            )
            Issue.record("Zero-angle revolve must fail.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .invalidInput)
            #expect(error.featureID == zeroFeatureID)
            #expect(error.tolerance == tolerance)
        }

        let excessiveFeatureID = FeatureID()
        do {
            _ = try PlanarRevolveFeatureEvaluator().evaluate(
                feature: revolveFeature(
                    id: excessiveFeatureID,
                    profileFeatureID: profileFeatureID,
                    angleDegrees: 361.0
                ),
                context: context
            )
            Issue.record("Revolve beyond one full turn must fail.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .unsupportedCapability)
            #expect(error.featureID == excessiveFeatureID)
            #expect(try #require(error.residual) > 0.0)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test
    func rationalProfileCrossingAxisReturnsFeatureScopedTypedDiagnostic() throws {
        let profileFeatureID = FeatureID()
        let featureID = FeatureID()
        let curve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.01, y: 0.0, z: 0.0),
                Point3D(x: -0.05, y: 0.005, z: 0.0),
                Point3D(x: -0.05, y: 0.015, z: 0.0),
                Point3D(x: 0.01, y: 0.02, z: 0.0),
            ],
            weights: [1.0, 0.5, 2.0, 1.0]
        )
        try curve.validate(tolerance: tolerance)
        let start = try curve.point(at: 0.0, tolerance: tolerance)
        let end = try curve.point(at: 1.0, tolerance: tolerance)
        let profile = Profile(
            sourceFeatureID: profileFeatureID,
            plane: .xy,
            vertices: [start, end],
            boundarySegments: [
                .spline(ProfileSplineSegment(curve: curve)),
                .line(ProfileLineSegment(start: end, end: start)),
            ]
        )

        do {
            _ = try PlanarRevolveFeatureEvaluator().evaluate(
                feature: revolveFeature(
                    id: featureID,
                    profileFeatureID: profileFeatureID,
                    angleDegrees: 180.0
                ),
                context: evaluationContext(
                    profileFeatureID: profileFeatureID,
                    profile: profile
                )
            )
            Issue.record("A revolve profile crossing the axis must fail.")
        } catch let error as KernelError {
            #expect(error.phase == .validation)
            #expect(error.code == .invalidInput)
            #expect(error.featureID == featureID)
            #expect(try #require(error.residual) > tolerance.distance)
            #expect(error.tolerance == tolerance)
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
                Point3D(x: -0.002, y: 0.005, z: 0.0),
                Point3D(x: 0.02, y: 0.015, z: 0.0),
                Point3D(x: 0.01, y: 0.02, z: 0.0),
            ],
            weights: [1.0, 0.2, 2.0, 1.0]
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

    private func multiSpanSplineProfile(featureID: FeatureID) throws -> Profile {
        let curve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.012, y: 0.0, z: 0.0),
                Point3D(x: 0.018, y: 0.004, z: 0.0),
                Point3D(x: 0.009, y: 0.009, z: 0.0),
                Point3D(x: 0.017, y: 0.016, z: 0.0),
                Point3D(x: 0.011, y: 0.022, z: 0.0),
            ],
            weights: [1.0, 0.4, 1.8, 0.7, 1.2]
        )
        try curve.validate(tolerance: tolerance)
        let samples = try (0...12).map { index in
            try curve.point(
                at: Double(index) / 12.0,
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
