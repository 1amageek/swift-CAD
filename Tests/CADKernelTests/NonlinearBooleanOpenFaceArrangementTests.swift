import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import Testing
@testable import CADKernel

@Suite("Nonlinear Boolean open-face arrangement")
struct NonlinearBooleanOpenFaceArrangementTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func exactSurfaceLiftPcurvesIntersectWithoutRationalModelCurveFallback() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let horizontal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: -0.020, y: 0.0),
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.020, y: 0.0),
            ],
            weights: [1.0, 1.2, 1.0]
        )
        let vertical = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: -0.020),
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.0, y: 0.020),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let first = try surfaceLiftEdge(
            stableID: "surface-lift-crossing:horizontal",
            surface: surface,
            parameterCurve: horizontal
        )
        let second = try surfaceLiftEdge(
            stableID: "surface-lift-crossing:vertical",
            surface: surface,
            parameterCurve: vertical
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            tolerance: tolerance
        )
        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Transverse surface-lift pcurves must not be classified as coincident.")
            return
        }
        let expected = try surface.point(u: 0.0, v: 0.0, tolerance: tolerance)
        #expect(points.count == 1)
        #expect(points[0].isApproximatelyEqual(to: expected, tolerance: tolerance.distance))
    }

    @Test(.timeLimit(.minutes(1)))
    func certifiedNonRationalTrimCurvesIntersectThroughExactSupportSurfaces() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let firstCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let secondCylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: -1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let expected = Point3D(
            x: 0.0,
            y: sqrt(1.25),
            z: sqrt(7.75)
        )
        let first = try certifiedIntersectionEdge(
            stableID: "certified-support:first",
            sharedSurface: sphere,
            otherSurface: firstCylinder,
            containing: expected
        )
        let second = try certifiedIntersectionEdge(
            stableID: "certified-support:second",
            sharedSurface: sphere,
            otherSurface: secondCylinder,
            containing: expected
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            sharedSurface: sphere,
            tolerance: tolerance
        )

        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Distinct certified trim loci must produce discrete intersections.")
            return
        }
        #expect(points.contains {
            $0.isApproximatelyEqual(to: expected, tolerance: tolerance.distance)
        })
        for point in points {
            #expect(try BRepSewingEdgeSubdivider().contains(
                point,
                on: first,
                tolerance: tolerance
            ))
            #expect(try BRepSewingEdgeSubdivider().contains(
                point,
                on: second,
                tolerance: tolerance
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonRationalSharedSurfacePcurvesIntersectWithoutRetainedSecondSupports() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let first = try sphericalGreatCircleEdge(
            stableID: "great-circle-crossing:equator",
            surface: sphere,
            cosine: .unitX,
            sine: .unitY
        )
        let second = try sphericalGreatCircleEdge(
            stableID: "great-circle-crossing:meridian",
            surface: sphere,
            cosine: .unitX,
            sine: .unitZ
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            sharedSurface: sphere,
            tolerance: tolerance
        )

        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Distinct great-circle spans must produce discrete intersections.")
            return
        }
        let expected = Point3D(x: 3.0, y: 0.0, z: 0.0)
        #expect(points.count == 1)
        #expect(points[0].isApproximatelyEqual(
            to: expected,
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidImagePcurvesOnProceduralSurfaceIntersectWithoutRationalFallback() throws {
        let sourceSurface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .bSpline(curvedBoundary(y: 0.0)),
            endBoundary: .bSpline(curvedBoundary(y: 1.0))
        )))
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.2, y: -0.1, z: 0.3),
            direction: Vector3D(x: 1.0, y: 2.0, z: -1.0),
            angle: 0.47,
            tolerance: tolerance
        )
        let targetSurface = try transform.applying(
            to: sourceSurface,
            tolerance: tolerance
        )
        let horizontal = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.1, y: 0.5),
                Point2D(x: 0.5, y: 0.5),
                Point2D(x: 0.9, y: 0.5),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let vertical = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.5, y: 0.1),
                Point2D(x: 0.5, y: 0.5),
                Point2D(x: 0.5, y: 0.9),
            ],
            weights: [1.0, 1.2, 1.0]
        )
        let first = try rigidImageEdge(
            stableID: "rigid-pcurve-crossing:horizontal",
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            sourcePcurve: .bSpline(horizontal),
            transform: transform
        )
        let second = try rigidImageEdge(
            stableID: "rigid-pcurve-crossing:vertical",
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            sourcePcurve: .bSpline(vertical),
            transform: transform
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            sharedSurface: targetSurface,
            tolerance: tolerance
        )

        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Distinct rigid-image pcurves must produce discrete intersections.")
            return
        }
        let expected = try targetSurface.point(
            u: 0.5,
            v: 0.5,
            tolerance: tolerance
        )
        #expect(points.count == 1)
        #expect(points[0].isApproximatelyEqual(
            to: expected,
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func coplanarCircularSpansUseTheirExactPlanarIntersections() throws {
        let first = try circularEdge(
            stableID: "coplanar-circle:first",
            center: .origin,
            radius: 2.0,
            startParameter: -Double.pi * 0.25,
            endParameter: Double.pi * 1.25
        )
        let second = try circularEdge(
            stableID: "coplanar-circle:second",
            center: Point3D(x: 2.0, y: 0.0, z: 0.0),
            radius: 2.0,
            startParameter: 0.0,
            endParameter: Double.pi
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            tolerance: tolerance
        )

        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Distinct circular loci must produce discrete intersections.")
            return
        }
        #expect(points.count == 2)
        #expect(points.allSatisfy { abs($0.x - 1.0) <= tolerance.distance })
        #expect(points.allSatisfy {
            abs(abs($0.y) - sqrt(3.0)) <= tolerance.distance
                && abs($0.z) <= tolerance.distance
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func disjointConcentricCircularSpansDoNotEnterRuledSurfaceSearch() throws {
        let first = try circularEdge(
            stableID: "concentric-circle:first",
            center: .origin,
            radius: 2.0,
            startParameter: 0.0,
            endParameter: Double.pi
        )
        let second = try circularEdge(
            stableID: "concentric-circle:second",
            center: .origin,
            radius: 1.0,
            startParameter: 0.0,
            endParameter: Double.pi
        )

        let result = try ExactTrimEdgeIntersector().intersections(
            first,
            second,
            tolerance: tolerance
        )

        guard case let .subdivisionPoints(points) = result else {
            Issue.record("Distinct concentric circles must not be coincident spans.")
            return
        }
        #expect(points.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticBoundaryUsesExactNonlinearCrossingSubdivision() throws {
        let fixture = try makeFixture()
        let boundary = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-arrangement:quadratic",
            startParameter: 0.0,
            endParameter: 1.0,
            segmentOrdinal: 0
        )

        let result = try build(fixture: fixture, boundaries: [boundary])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        #expect(patch.loops.count == 1)
        #expect(patch.loops[0].edges.contains { edge in
            if case .bSpline = edge.curve { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyOverlappingRationalBoundariesMergeExactSharedSpan() throws {
        let fixture = try makeFixture()
        let first = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-overlap:first",
            startParameter: 0.0,
            endParameter: 0.75,
            segmentOrdinal: 0
        )
        let second = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-overlap:second",
            startParameter: 0.25,
            endParameter: 1.0,
            segmentOrdinal: 1
        )

        let result = try build(fixture: fixture, boundaries: [first, second])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        let splineEdges = patch.loops.flatMap(\.edges).filter { edge in
            if case .bSpline = edge.curve { return true }
            return false
        }
        #expect(splineEdges.count == 3)
        #expect(splineEdges.contains { edge in
            abs(edge.startParameter - 0.25) <= tolerance.relative
                && abs(edge.endParameter - 0.75) <= tolerance.relative
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func quadraticBoundaryTangentToSourceEdgeBuildsValidatedRegion() throws {
        let fixture = try makeFixture(controlY: 0.020)
        let boundary = try makeBoundary(
            fixture: fixture,
            stableID: "nonlinear-tangent:quadratic",
            startParameter: 0.0,
            endParameter: 1.0,
            segmentOrdinal: 0,
            forwardLeftAction: .discard,
            forwardRightAction: .keep
        )

        let result = try build(fixture: fixture, boundaries: [boundary])

        #expect(result.isPartitioned)
        #expect(result.patches.count == 1)
        let patch = try #require(result.patches.first)
        try patch.validate(tolerance: tolerance)
        let splineEdges = patch.loops.flatMap(\.edges).filter { edge in
            if case .bSpline = edge.curve { return true }
            return false
        }
        #expect(splineEdges.count == 2)
        let tangentPoint = try fixture.curve.point(
            at: 0.5,
            tolerance: tolerance
        )
        #expect(splineEdges.contains { edge in
            edge.startPoint.isApproximatelyEqual(
                to: tangentPoint,
                tolerance: tolerance.distance
            ) || edge.endPoint.isApproximatelyEqual(
                to: tangentPoint,
                tolerance: tolerance.distance
            )
        })
    }

    private func build(
        fixture: Fixture,
        boundaries: [BooleanFaceArrangementBoundary]
    ) throws -> BooleanOpenFaceArrangementBuilder.Result {
        try BooleanOpenFaceArrangementBuilder().build(
            faceID: fixture.face.id,
            boundaries: boundaries,
            model: fixture.source.brep,
            sourceSubshapes: fixture.source.subshapes.entries,
            tolerance: tolerance
        )
    }

    private func makeFixture(controlY: Double = 0.006) throws -> Fixture {
        let source = try PlanarSheetTestFixture.make(
            featureID: FeatureID(),
            tolerance: tolerance
        )
        let body = try #require(source.brep.bodies.values.first)
        let shell = try #require(source.brep.shells[body.shellIDs[0]])
        let face = try #require(source.brep.faces[shell.faceIDs[0]])
        let surface = try #require(source.brep.geometry.surfaces[face.surfaceID])
        let controlPoints = [
            Point3D(x: -0.020, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: controlY, z: 0.0),
            Point3D(x: 0.020, y: 0.0, z: 0.0),
        ]
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: controlPoints,
            weights: [1.0, 1.0, 1.0]
        )
        try curve.validate(tolerance: tolerance)
        let projectedControls = try controlPoints.map { point in
            let parameter = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            return Point2D(x: parameter.u, y: parameter.v)
        }
        let pcurve = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: projectedControls,
            weights: curve.weights
        )
        try pcurve.validate(tolerance: tolerance)
        return Fixture(
            source: source,
            face: face,
            curve: curve,
            pcurve: pcurve
        )
    }

    private func makeBoundary(
        fixture: Fixture,
        stableID: String,
        startParameter: Double,
        endParameter: Double,
        segmentOrdinal: Int,
        forwardLeftAction: BooleanRegionSelectionAction = .keep,
        forwardRightAction: BooleanRegionSelectionAction = .discard
    ) throws -> BooleanFaceArrangementBoundary {
        let pair = BooleanFacePairCandidate(
            targetFaceID: fixture.face.id,
            toolFaceID: FaceID()
        )
        let startPoint = try fixture.curve.point(
            at: startParameter,
            tolerance: tolerance
        )
        let endPoint = try fixture.curve.point(
            at: endParameter,
            tolerance: tolerance
        )
        let pcurve = try fixture.pcurve.trimmed(
            from: startParameter,
            to: endParameter,
            tolerance: tolerance
        )
        return BooleanFaceArrangementBoundary(
            reference: BooleanFaceSplitComponentReference(
                facePair: pair,
                componentID: BooleanFaceSplitComponentID(ordinal: segmentOrdinal)
            ),
            segmentOrdinal: segmentOrdinal,
            faceID: fixture.face.id,
            edge: BRepSewingEdge(
                stableID: stableID,
                curve: .bSpline(fixture.curve),
                startParameter: startParameter,
                endParameter: endParameter,
                startPoint: startPoint,
                endPoint: endPoint,
                surfaceParameterCurve: .bSpline(pcurve)
            ),
            forwardLeftAction: forwardLeftAction,
            forwardRightAction: forwardRightAction
        )
    }

    private func surfaceLiftEdge(
        stableID: String,
        surface: Surface3D,
        parameterCurve: BSplineCurve2D
    ) throws -> BRepSewingEdge {
        let pcurve = SurfaceParameterCurve.bSpline(parameterCurve)
        let lift = SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve)
        try lift.validate(tolerance: tolerance)
        let curve = Curve3D.surfaceLift(lift)
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private func circularEdge(
        stableID: String,
        center: Point3D,
        radius: Double,
        startParameter: Double,
        endParameter: Double
    ) throws -> BRepSewingEdge {
        let curve = Curve3D.analytic(.circle(
            center: center,
            normal: .unitZ,
            radius: radius
        ))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: try curve.point(at: startParameter, tolerance: tolerance),
            endPoint: try curve.point(at: endParameter, tolerance: tolerance),
            surfaceParameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.0),
                startParameter: startParameter,
                endParameter: endParameter
            )
        )
    }

    private func sphericalGreatCircleEdge(
        stableID: String,
        surface: Surface3D,
        cosine: Vector3D,
        sine: Vector3D
    ) throws -> BRepSewingEdge {
        let pcurve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: cosine,
            sine: sine,
            startParameter: -Double.pi * 0.5,
            endParameter: Double.pi * 0.5
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: pcurve
        ))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private func curvedBoundary(y: Double) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: y, z: 0.0),
                Point3D(x: 0.5, y: y, z: 0.15),
                Point3D(x: 1.0, y: y, z: 0.4),
            ]
        )
    }

    private func rigidImageEdge(
        stableID: String,
        sourceSurface: Surface3D,
        targetSurface: Surface3D,
        sourcePcurve: SurfaceParameterCurve,
        transform: RigidTransform3D
    ) throws -> BRepSewingEdge {
        let sourceLift = SurfaceLiftCurve3D(
            surface: sourceSurface,
            parameterCurve: sourcePcurve
        )
        let image = try RigidImageSurfaceParameterCurve(
            source: sourceLift,
            targetSurface: targetSurface,
            transform: transform,
            tolerance: tolerance
        )
        let pcurve = SurfaceParameterCurve.rigidImage(image)
        let curve = Curve3D.rigidImage(try RigidImageCurve3D(
            source: .surfaceLift(sourceLift),
            transform: transform,
            tolerance: tolerance
        ))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try curve.point(at: 0.0, tolerance: tolerance),
            endPoint: try curve.point(at: 1.0, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private func certifiedIntersectionEdge(
        stableID: String,
        sharedSurface: Surface3D,
        otherSurface: Surface3D,
        containing expectedPoint: Point3D
    ) throws -> BRepSewingEdge {
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: sharedSurface,
            second: otherSurface,
            tolerance: tolerance
        )
        var selected: (
            curve: SurfaceSurfaceIntersectionCurve,
            projection: CurveParameterProjection
        )?
        for intersection in intersections {
            guard case let .curve(curve) = intersection,
                  case let .surfaceLift(lift) = curve.curve,
                  case .certifiedAnalyticPair = lift.parameterCurve else {
                continue
            }
            do {
                let projection = try curve.curve.parameterProjection(
                    of: expectedPoint,
                    tolerance: tolerance
                )
                if selected == nil
                    || projection.residual < selected!.projection.residual {
                    selected = (curve, projection)
                }
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        guard let selected,
              selected.projection.residual <= tolerance.distance,
              case let .closed(domainLower, domainUpper)
                = selected.curve.curve.parameterDomain else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "The certified test fixture could not locate the expected triple-surface point."
            )
        }
        let domainWidth = domainUpper - domainLower
        let trimRadius = domainWidth * 0.125
        var trimLower = max(
            domainLower,
            selected.projection.parameter - trimRadius
        )
        var trimUpper = min(
            domainUpper,
            selected.projection.parameter + trimRadius
        )
        if trimUpper - trimLower < trimRadius {
            if trimLower == domainLower {
                trimUpper = min(domainUpper, trimLower + trimRadius * 2.0)
            } else {
                trimLower = max(domainLower, trimUpper - trimRadius * 2.0)
            }
        }
        let pcurve = try selected.curve.firstSurfaceParameterCurve.trimmed(
            from: trimLower,
            to: trimUpper,
            curveDomain: selected.curve.curve.parameterDomain,
            tolerance: tolerance
        )
        return BRepSewingEdge(
            stableID: stableID,
            curve: selected.curve.curve,
            startParameter: trimLower,
            endParameter: trimUpper,
            startPoint: try selected.curve.curve.point(
                at: trimLower,
                tolerance: tolerance
            ),
            endPoint: try selected.curve.curve.point(
                at: trimUpper,
                tolerance: tolerance
            ),
            surfaceParameterCurve: pcurve
        )
    }

    private struct Fixture {
        let source: PlanarSheetTestFixture
        let face: Face
        let curve: BSplineCurve3D
        let pcurve: BSplineCurve2D
    }
}
