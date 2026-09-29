import Testing
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Rolling-ball whole-body composition", .timeLimit(.minutes(2)))
struct RollingBallFilletRequestBuilderTests {
    @Test func quadraticTerminalIntersectionIsBounded() throws {
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        let source = Surface3D.bSpline(BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 0.01].map { z in
                [Point3D(x: -0.02, y: 0, z: z), Point3D(x: -0.01, y: -0.01, z: z),
                 Point3D(x: 0, y: -0.01, z: z)]
            }, weights: [[1, 1, 1], [1, 1, 1]]))
        let extended = try RollingBallFilletRequestBuilder.continued(source,
            along: .constantV(v: 1, uStart: 0, uEnd: 1), tolerance: tolerance)
        let first = OffsetSurface3D(source: extended, distance: -0.001)
        let second = OffsetSurface3D(source: .plane(.init(
            origin: Point3D(x: 0, y: 0, z: 0.01), normal: .unitZ)), distance: -0.001)
        let contacts = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.offset(first)), second: .procedural(.offset(second)), tolerance: tolerance)
        guard contacts.count == 1, case .curve(let contact) = contacts[0],
              case .closed(let lower, let upper) = contact.curve.parameterDomain else {
            Issue.record("A quadratic lateral span must have one bounded cap contact."); return
        }
        let blend = try RollingBallSectionEvaluator(first: first, second: second,
            intersection: contact, tolerance: tolerance).blendSurface(
                fromCurveParameter: lower, toCurveParameter: upper,
                options: .init(maximumSubdivisionDepth: 20, maximumCellCount: 65_536))
        let neighbor = Surface3D.bSpline(BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 0.01].map { z in
                [Point3D(x: -0.02, y: 0, z: z), Point3D(x: -0.02, y: 0.03, z: z)]
            }, weights: [[1, 1], [1, 1]]))
        let extendedNeighbor = try RollingBallFilletRequestBuilder.continued(
            neighbor, along: nil, tolerance: tolerance)
        let result = try DefaultSurfaceSurfaceIntersector().intersections(
            first: .procedural(.rollingBall(blend)),
            second: extendedNeighbor,
            options: .init(maximumSubdivisionCells: 4096, maximumRootAttempts: 4096), tolerance: tolerance)
        #expect(result.count == 1)
        guard let firstResult = result.first, case .curve(let terminal) = firstResult,
              case .implicit(let curve) = terminal.truth else {
            Issue.record("A terminal must retain its certified spatial intersection."); return
        }
        for fraction in [0.0, 0.5, 1.0] {
            let uv = try curve.parameterPair(atNormalizedFraction: fraction, tolerance: tolerance)
            let onBlend = try blend.point(u: uv.first.u, v: uv.first.v)
            let onNeighbor = try extendedNeighbor.point(u: uv.second.u, v: uv.second.v, tolerance: tolerance)
            #expect((onBlend - onNeighbor).length <= tolerance.distance)
            #expect(abs(onBlend.x + 0.02) <= tolerance.distance)
        }
        let start = try curve.parameterPair(atNormalizedFraction: 0, tolerance: tolerance)
        let end = try curve.parameterPair(atNormalizedFraction: 1, tolerance: tolerance)
        #expect(abs(abs(end.first.v - start.first.v) - 1) <= tolerance.relative * 10)
    }

    @Test func continuationFollowsSelectedBoundaryAcrossTransposedCharts() throws {
        let tolerance = ModelingTolerance.standard
        let points = [
            [Point3D(x: 0, y: 0, z: 0), Point3D(x: 2, y: 0, z: 1)],
            [Point3D(x: 0, y: 3, z: 0), Point3D(x: 2, y: 3, z: 2)],
        ]
        let original = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 2, 2], vKnots: [0, 0, 3, 3],
            controlPoints: points, weights: [[1, 1], [1, 1]])
        let transposed = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: original.vKnots, vKnots: original.uKnots,
            controlPoints: points[0].indices.map { column in points.map { $0[column] } },
            weights: [[1, 1], [1, 1]])
        let boundary = SurfaceParameterCurve.constantV(v: 3, uStart: 0, uEnd: 2)
        let extended = try RollingBallFilletRequestBuilder.continued(.bSpline(original),
            along: boundary, tolerance: tolerance)
        let swapped = try RollingBallFilletRequestBuilder.continued(.bSpline(transposed),
            along: .constantU(u: 3, vStart: 2, vEnd: 0), tolerance: tolerance)
        guard case .bSpline(let a) = extended, case .bSpline(let b) = swapped else {
            Issue.record("Continuation must preserve a Bezier support."); return
        }
        #expect(a.uDomain == .closed(-0.5, 2.5))
        #expect(a.vDomain == original.vDomain)
        #expect(a.uDomain == b.vDomain)
        #expect(a.vDomain == b.uDomain)
        for u in [-0.5, 0, 1, 2, 2.5] {
            for v in [0.0, 1.5, 3] {
                let first = try extended.point(u: u, v: v, tolerance: tolerance)
                let second = try swapped.point(u: v, v: u, tolerance: tolerance)
                #expect((first - second).length <= tolerance.distance * 0.01)
            }
        }
        #expect(try extended == RollingBallFilletRequestBuilder.continued(.bSpline(original),
            along: .constantV(v: 3, uStart: 2, uEnd: 0), tolerance: tolerance))
        for invalid in [SurfaceParameterCurve.constantU(u: 1, vStart: 0, vEnd: 3),
                        .constantV(v: 3, uStart: 0, uEnd: 1)] {
            #expect(throws: KernelError.self) {
                try RollingBallFilletRequestBuilder.continued(.bSpline(original),
                    along: invalid, tolerance: tolerance)
            }
        }
    }

    @Test func curvedSourceRetainsCompleteSolidAndRejectsInvalidSelection() throws {
        let tolerance = ModelingTolerance(distance: 1e-8, angle: 1e-10, relative: 1e-10)
        let profileID = FeatureID()
        func point(_ x: Double, _ y: Double) -> Point3D { Point3D(x: x, y: y, z: 0) }
        let controls = [
            [point(-0.02, 0), point(-0.01, -0.01), point(0, -0.01)],
            [point(0, -0.01), point(0.01, -0.01), point(0.02, 0)],
            [point(0.02, 0), point(0.02, 0.03)],
            [point(0.02, 0.03), point(-0.02, 0.03)],
            [point(-0.02, 0.03), point(-0.02, 0)],
        ]
        let curves = controls.map { points in
            BSplineCurve3D(degree: points.count - 1,
                knots: Array(repeating: 0, count: points.count) + Array(repeating: 1, count: points.count),
                controlPoints: points, weights: Array(repeating: 1, count: points.count))
        }
        let vertices = try curves.flatMap { curve in
            try (0..<4).map { try curve.point(at: Double($0) / 4, tolerance: tolerance) }
        }
        let profile = Profile(sourceFeatureID: profileID, plane: .xy, vertices: vertices,
            boundarySegments: curves.map { .spline(.init(curve: $0)) })
        let feature = FeatureNode(id: FeatureID(), operation: .extrude(.init(
            profile: .init(featureID: profileID), distance: .constant(.length(0.01, unit: .meter)),
            direction: .vector(Vector3D(x: 0, y: 0, z: 1)))),
            inputs: [.init(featureID: profileID, role: .profile)], outputs: [.init(role: .body)])
        let evaluated = try PlanarExtrudeFeatureEvaluator(sewer: DefaultBRepSewer()).evaluateValidated(
            feature: feature, context: .init(parameters: .init(), brep: .init(),
                profiles: [profileID: [profile]], tolerance: tolerance))
        let source = evaluated.result
        let certified = evaluated.brep
        let bodyID = try #require(source.brep.bodies.keys.first)
        let lateral = try #require(source.brep.faces.values.first { face in
            guard case .bSpline(let surface) = source.brep.geometry.surfaces[face.surfaceID] else { return false }
            return surface.uDegree == 2 && surface.controlPoints[0][0].x < -0.01
        })
        let lateralEdges = Set(lateral.loops.flatMap { source.brep.loops[$0]?.edges.map(\.edgeID) ?? [] })
        let cap = try #require(source.brep.faces.values.first { face in
            guard case .plane(let plane) = source.brep.geometry.surfaces[face.surfaceID],
                  plane.origin.z > 0.005 else { return false }
            return face.loops.contains { source.brep.loops[$0]?.edges.contains { lateralEdges.contains($0.edgeID) } == true }
        })
        let selected = try #require(cap.loops.flatMap { source.brep.loops[$0]?.edges ?? [] }.first {
            lateralEdges.contains($0.edgeID)
        })
        let builder = RollingBallFilletRequestBuilder(input: certified, subshapes: source.subshapes)
        for radius in [0.0, -0.001, .nan, .infinity] {
            #expect(throws: KernelError.self) {
                try builder.build(featureID: FeatureID(), bodyID: bodyID, edgeID: selected.edgeID, radius: radius)
            }
        }
        #expect(throws: KernelError.self) {
            try builder.build(featureID: FeatureID(), bodyID: bodyID, edgeID: EdgeID(), radius: 0.001)
        }
        let request = try builder.build(featureID: FeatureID(), bodyID: bodyID,
            edgeID: selected.edgeID, radius: 0.001)
        #expect(request.bodyKind == .solid)
        #expect(request.shells.count == 1)
        let patches = try #require(request.shells.first).patches
        #expect(patches.count == source.brep.faces.count + 2)
        for (id, reference) in source.subshapes {
            guard case .face(let faceID) = reference else { continue }
            let surfaceID = try #require(source.brep.faces[faceID]).surfaceID
            #expect(patches.contains { $0.parentSubshapeIDs.contains(id)
                && $0.surface == source.brep.geometry.surfaces[surfaceID] })
        }
        let result = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        #expect(result.validatedBRep.validationLevel == .exact)
        #expect(result.brep.bodies[result.bodyID]?.kind == .solid)
        let uses = Dictionary(grouping: result.brep.loops.values.flatMap(\.edges), by: \.edgeID)
        #expect(uses.values.allSatisfy { $0.count == 2 && $0[0].orientation != $0[1].orientation })
        let volume = try result.brep.volume(tolerance: tolerance)
        let sourceVolume = try source.brep.volume(tolerance: tolerance)
        #expect(volume > 0 && volume < sourceVolume)
        #expect(certified.model == source.brep)
    }
}
