import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADModeling

@Suite("Original cubic extrusion draft proof")
struct OriginalCubicExtrusionDraftTests {
    private let points = [Point3D(x: 0.03, y: -0.01, z: 0.01), Point3D(x: 0.03, y: -0.003, z: 0.012),
                          Point3D(x: 0.03, y: 0.003, z: 0.008), Point3D(x: 0.03, y: 0.01, z: 0.01)]
    private func inputs(transposed: Bool = false, controls: [Point3D]? = nil) -> (Curve3D, Surface3D) {
        let controls = controls ?? points
        let base = controls.map { Point3D(x: 0, y: $0.y, z: $0.z) }
        let knots = [0.0, 0, 0, 0, 1, 1, 1, 1]
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 3, knots: knots, controlPoints: controls))
        let surface = transposed
            ? BSplineSurface3D(uDegree: 1, vDegree: 3, uKnots: [0, 0, 1, 1], vKnots: knots,
                               controlPoints: zip(base, controls).map { [$0, $1] })
            : BSplineSurface3D(uDegree: 3, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1], controlPoints: [base, controls])
        return (curve, .bSpline(surface))
    }
    private func construct(transposed: Bool = false, start: Double = 0, end: Double = 1,
                           tolerance: ModelingTolerance = .standard) throws -> CurvedHingeDraftSurfaceBuilder.Construction {
        let (hinge, reference) = inputs(transposed: transposed)
        return try CurvedHingeDraftSurfaceBuilder(tolerance: tolerance).construction(
            hinge: hinge, start: start, end: end, reference: reference,
            referenceSign: transposed ? 1 : -1, outward: .unitX, angle: .pi / 6, reach: 0.05)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func literalOriginalCubicAndBothCarryNormalsAreCertified(transposed: Bool) throws {
        let result = try construct(transposed: transposed)
        let receipt = try #require(result.receipt)
        #expect(receipt.maximumPositionError <= ModelingTolerance.standard.distance / 8)
        #expect(receipt.maximumRulingError <= ModelingTolerance.standard.angle)
        #expect(receipt.spans.first?.lower == 0)
        #expect(receipt.spans.last?.upper == 1)
        #expect(zip(receipt.spans, receipt.spans.dropFirst()).allSatisfy { $0.upper == $1.lower })
        for s in [0.031, 0.137, 0.223, 0.317, 0.463, 0.611, 0.739, 0.877, 0.971] {
            let t = min(max((s - 0.2) / (0.8 - 0.2), 0), 1)
            let y = -0.01 + 0.021 * t - 0.003 * t * t + 0.002 * t * t * t
            let z = 0.01 + 0.006 * t - 0.018 * t * t + 0.012 * t * t * t
            let dy = 0.021 - 0.006 * t + 0.006 * t * t
            let dz = 0.006 - 0.036 * t + 0.036 * t * t
            let q = hypot(dy, dz)
            var original = Point3D(x: 0.03, y: y, z: z)
            if s < 0.2 { original = original + Vector3D(x: 0, y: dy / q, z: dz / q) * (0.025 * (s - 0.2) / 0.2) }
            if s > 0.8 { original = original + Vector3D(x: 0, y: dy / q, z: dz / q) * (0.025 * (s - 0.8) / 0.2) }
            let direction = Vector3D(x: tan(.pi / 6), y: dz / q, z: -dy / q)
            for v in [0.0, 0.173, 0.529, 0.911, 1] {
                let d = -0.0025 + 0.0775 * v
                let actual = try result.surface.point(u: s, v: v, tolerance: .standard)
                #expect((actual - (original + direction * d)).length <= ModelingTolerance.standard.distance / 8)
            }
            let a = try result.surface.point(u: s, v: 0, tolerance: .standard)
            let b = try result.surface.point(u: s, v: 1, tolerance: .standard)
            let running = b - a
            #expect(atan2(running.cross(direction).length, running.dot(direction)) <= ModelingTolerance.standard.angle)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalReversedTrimKeepsTheSameGeometricNormal() throws {
        let result = try construct(start: 1, end: 0)
        let receipt = try #require(result.receipt)
        try DefaultCurveSurfaceCorrespondenceValidator().validate(curve: receipt.hinge, from: 1, to: 0,
            surface: receipt.surface, parameterCurve: receipt.hingePcurve,
            options: CurveSurfaceCorrespondenceValidationOptions(maximumSubdivisionDepth: 32,
                maximumCellCount: 65_536, maximumDeviation: ModelingTolerance.standard.distance / 4), tolerance: .standard)
        let actual = try result.surface.point(u: 0.5, v: 0, tolerance: .standard)
        #expect(abs(actual.y - (0.0025 * 0.003 / hypot(0.0195, 0.003))) <= ModelingTolerance.standard.distance / 8)
    }

    @Test(.timeLimit(.minutes(1)))
    func positionalAgreementCannotAuthorizeAPerturbedRuling() throws {
        typealias I = OutwardScalarInterval
        let (hinge, reference) = inputs()
        let law = try #require(try CurvedHingeDraftSurfaceBuilder.OriginalLaw(hinge: hinge, reference: reference,
            start: 0, end: 1, referenceSign: -1, outward: .unitX, angle: .pi / 6, reach: 0.05, tolerance: .standard))
        let a = 0.41, b = 0.410001
        let first = try #require(try law.jets(over: .exact(a), region: .native))
        let last = try #require(try law.jets(over: .exact(b), region: .native))
        let whole = try #require(try law.jets(over: I(lower: a, upper: b), region: .native))
        let width = I.exact(b) - .exact(a)
        let third = try #require(width.divided(by: .exact(3)))
        let ideal = [first.direction.derivative(0),
                     zip(first.direction.derivative(0), first.direction.derivative(1)).map { $0 + $1 * third },
                     zip(last.direction.derivative(0), last.direction.derivative(1)).map { $0 - $1 * third }, last.direction.derivative(0)]
        let perturbation = Vector3D(x: 0, y: 1e-6, z: 0)
        let candidate = ideal.map { Point3D(x: $0[0].midpoint, y: $0[1].midpoint, z: $0[2].midpoint) + perturbation }
        let error = CurvedHingeDraftSurfaceBuilder.error(controls: candidate, lowerJet: first.direction,
            upperJet: last.direction, wholeJet: whole.direction, width: width)
        #expect(0.075 * perturbation.length < ModelingTolerance.standard.distance / 8)
        #expect(error > ModelingTolerance.standard.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceOutputTrimAndToleranceCannotBorrowAReceipt() throws {
        let receipt = try #require(try construct().receipt)
        var changed = points; changed[2].z += 0.001
        let (_, otherReference) = inputs(controls: changed)
        #expect(throws: KernelError.self) {
            try receipt.validate(hinge: receipt.hinge, reference: otherReference, start: 0, end: 1,
                referenceSign: -1, output: receipt.surface, tolerance: .standard)
        }
        #expect(throws: KernelError.self) {
            try receipt.validate(hinge: receipt.hinge, reference: receipt.reference, start: 0.01, end: 1,
                referenceSign: -1, output: receipt.surface, tolerance: .standard)
        }
        #expect(throws: KernelError.self) {
            try receipt.validate(hinge: receipt.hinge, reference: receipt.reference, start: 0, end: 1,
                referenceSign: -1, output: .plane(Plane3D(origin: .origin, normal: .unitZ)), tolerance: .standard)
        }
        var different = ModelingTolerance.standard; different.distance *= 2
        #expect(throws: KernelError.self) {
            try receipt.validate(hinge: receipt.hinge, reference: receipt.reference, start: 0, end: 1,
                referenceSign: -1, output: receipt.surface, tolerance: different)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func zeroOriginalEndpointTangentAndUnprovedAccuracyRefuse() throws {
        var collapsed = points; collapsed[1] = collapsed[0]
        let (hinge, reference) = inputs(controls: collapsed)
        #expect(throws: KernelError.self) {
            do {
                _ = try CurvedHingeDraftSurfaceBuilder(tolerance: .standard).construction(hinge: hinge,
                    start: 0, end: 1, reference: reference, referenceSign: -1, outward: .unitX, angle: .pi / 6, reach: 0.05)
            } catch let error as KernelError { #expect(error.code == .singularGeometry); throw error }
        }
        #expect(throws: KernelError.self) {
            do { _ = try construct(tolerance: ModelingTolerance(distance: 1e-30, angle: 1e-30, relative: 1e-9)) }
            catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); throw error }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func completeFloorAndSideCoversKeepAllAdmittedSpans() throws {
        let receipt = try #require(try construct().receipt)
        let helper = RuledBSplinePlaneSection(tolerance: .standard)
        let floor = try helper.sections(of: receipt, by: Plane3D(origin: .origin, normal: .unitZ))
        #expect(floor.count == 1)
        #expect(floor.first?.curve.knots.first == 0)
        #expect(floor.first?.curve.knots.last == 1)
        let sides = try helper.sections(of: receipt, by: Plane3D(origin: Point3D(x: 0, y: 0.01, z: 0), normal: .unitY))
        #expect(!sides.isEmpty)
        #expect(sides.last?.curve.knots.last == 1)
        let absent = try helper.sections(of: receipt, by: Plane3D(origin: Point3D(x: 1, y: 0, z: 0), normal: .unitX))
        #expect(absent.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func aParallelContactCannotBeDiscardedAsNoCut() throws {
        let straight = [Point3D(x: 0.03, y: -0.01, z: 0.01), Point3D(x: 0.03, y: -0.003, z: 0.01),
                        Point3D(x: 0.03, y: 0.003, z: 0.01), Point3D(x: 0.03, y: 0.01, z: 0.01)]
        let (hinge, reference) = inputs(controls: straight)
        let receipt = try #require(try CurvedHingeDraftSurfaceBuilder(tolerance: .standard).construction(
            hinge: hinge, start: 0, end: 1, reference: reference, referenceSign: -1,
            outward: .unitX, angle: .pi / 6, reach: 0.05).receipt)
        #expect(throws: KernelError.self) {
            do {
                _ = try RuledBSplinePlaneSection(tolerance: .standard).sections(of: receipt,
                    by: Plane3D(origin: .origin, normal: .unitY))
            } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded); throw error }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unchangedNonAffineSupportKeepsItsOriginalRetrimmedChart() throws {
        for reversed in [false, true] { try exerciseRetainedChart(reversed: reversed, invalid: false) }
    }

    @Test(.timeLimit(.minutes(1)))
    func invalidOriginalRetrimmedChartFailsTheActualReplacementPath() throws {
        #expect(throws: KernelError.self) {
            do { try exerciseRetainedChart(reversed: false, invalid: true) }
            catch let error as KernelError {
                #expect(error.message.hasPrefix("Retained original coedge actual trim:"))
                throw error
            }
        }
    }

    private func exerciseRetainedChart(reversed: Bool, invalid: Bool) throws {
        let (_, reference) = inputs()
        let origin = Vertex(point: Point3D(x: 0, y: -0.01, z: 0.01))
        let corner = Vertex(point: Point3D(x: 0.03, y: -0.01, z: 0.01))
        let bottom = Vertex(point: Point3D(x: 0.03, y: -0.01, z: 0))
        let sideCurveID = CurveID(), changedCurveID = CurveID()
        let sideCurve = Curve3D.line(Line3D(origin: origin.point, direction: .unitX))
        let changedCurve = Curve3D.line(Line3D(origin: bottom.point, direction: .unitZ))
        let sideEdge = Edge(curveID: sideCurveID, startVertexID: origin.id, endVertexID: corner.id,
                            trim: CurveTrim(startParameter: 0, endParameter: 0.03))
        let changedEdge = Edge(curveID: changedCurveID, startVertexID: bottom.id, endVertexID: corner.id,
                               trim: CurveTrim(startParameter: 0, endParameter: 0.01))
        let chart = SurfaceParameterCurve.constantU(u: invalid ? 0.5 : 0,
            vStart: reversed ? 1 : 0, vEnd: reversed ? 0 : 1)
        let neutralLoop = Loop(edges: [Coedge(edgeID: sideEdge.id,
            orientation: reversed ? .reversed : .forward, surfaceParameterCurve: chart)])
        let changedLoop = Loop(edges: [Coedge(edgeID: changedEdge.id)])
        let sidePlane = Surface3D.plane(Plane3D(origin: Point3D(x: 0, y: -0.01, z: 0), normal: .unitY))
        let onSide = try ExactFacePcurveBuilder().surfaceParameterCurve(for: sideCurve,
            startParameter: reversed ? 0 : 0.03, endParameter: reversed ? 0.03 : 0,
            on: sidePlane, tolerance: .standard)
        let sideLoop = Loop(edges: [Coedge(edgeID: changedEdge.id, orientation: .reversed),
            Coedge(edgeID: sideEdge.id, orientation: reversed ? .forward : .reversed, surfaceParameterCurve: onSide)])
        let neutralID = SurfaceID(), sideID = SurfaceID(), changedID = SurfaceID()
        let neutralFace = Face(surfaceID: neutralID, loops: [neutralLoop.id], orientation: .reversed)
        let sideFace = Face(surfaceID: sideID, loops: [sideLoop.id])
        let changedFace = Face(surfaceID: changedID, loops: [changedLoop.id])
        let shell = Shell(faceIDs: [neutralFace.id, sideFace.id, changedFace.id])
        let body = Body(sheetShellIDs: [shell.id])
        // This owner graph isolates actual retrimming and coedge publication, not solid closure.
        var model = BRepModel(geometry: GeometryStore(curves: [sideCurveID: sideCurve, changedCurveID: changedCurve],
            surfaces: [neutralID: reference, sideID: sidePlane,
                       changedID: .plane(Plane3D(origin: Point3D(x: 0.03, y: 0, z: 0), normal: .unitX))]),
            bodies: [body.id: body], shells: [shell.id: shell],
            faces: [neutralFace.id: neutralFace, sideFace.id: sideFace, changedFace.id: changedFace],
            loops: [neutralLoop.id: neutralLoop, sideLoop.id: sideLoop, changedLoop.id: changedLoop],
            edges: [sideEdge.id: sideEdge, changedEdge.id: changedEdge],
            vertices: [origin.id: origin, corner.id: corner, bottom.id: bottom])
        try FaceSurfaceReplacementRebuilder().replace([changedFace.id: .init(
            surface: .plane(Plane3D(origin: Point3D(x: 0.02, y: 0, z: 0), normal: .unitX)), orientation: .forward)],
            bodyID: body.id, featureID: FeatureID(), model: &model, tolerance: .standard,
            knownPoints: [corner.id: Point3D(x: 0.02, y: -0.01, z: 0.01), bottom.id: Point3D(x: 0.02, y: -0.01, z: 0)])
        let actual = try #require(model.edges[sideEdge.id]?.trim)
        #expect(abs(actual.endParameter - 0.02) <= 1e-12)
        let retained = try #require(model.loops[neutralLoop.id]?.coedges.first?.surfaceParameterCurve)
        let first = try retained.parameter(atNormalizedFraction: 0, tolerance: .standard)
        let last = try retained.parameter(atNormalizedFraction: 1, tolerance: .standard)
        #expect(abs(first.v - (reversed ? 2.0 / 3 : 0)) <= 1e-12)
        #expect(abs(last.v - (reversed ? 0 : 2.0 / 3)) <= 1e-12)
        #expect(model.loops[sideLoop.id]?.coedges.last?.surfaceParameterCurve != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func originalTwoPointChartsExtendThroughActualPlaneReplacement() throws {
        for reversed in [false, true] { try exerciseTwoPointExtension(reversed: reversed, invalid: false, threePoints: false) }
    }

    @Test(.timeLimit(.minutes(1)))
    func extendedWrongAndThreePointChartsCannotBorrowAffineAuthority() throws {
        #expect(throws: KernelError.self) { try exerciseTwoPointExtension(reversed: false, invalid: true, threePoints: false) }
        #expect(throws: KernelError.self) {
            do { try exerciseTwoPointExtension(reversed: false, invalid: false, threePoints: true) }
            catch let error as KernelError { #expect(error.code == .unsupportedCapability); throw error }
        }
    }

    private func exerciseTwoPointExtension(reversed: Bool, invalid: Bool, threePoints: Bool) throws {
        let corner = Vertex(point: Point3D(x: 0, y: 0, z: 0.01))
        let far = Vertex(point: Point3D(x: 0.03, y: 0, z: 0.01))
        let bottom = Vertex(point: .origin)
        let oldCurve = Curve3D.line(Line3D(origin: corner.point, direction: .unitX))
        let changedCurve = Curve3D.line(Line3D(origin: .origin, direction: .unitZ))
        let oldID = CurveID(), changedID = CurveID()
        let edge = Edge(curveID: oldID, startVertexID: corner.id, endVertexID: far.id,
                        trim: CurveTrim(startParameter: 0, endParameter: 0.03))
        let changed = Edge(curveID: changedID, startVertexID: bottom.id, endVertexID: corner.id,
                           trim: CurveTrim(startParameter: 0, endParameter: 0.01))
        var uv = [SurfaceParameter(u: 0, v: 0), SurfaceParameter(u: 0.03, v: invalid ? 0.001 : 0)]
        if threePoints { uv.insert(SurfaceParameter(u: 0.015, v: 0), at: 1) }
        if reversed { uv.reverse() }
        let floorLoop = Loop(edges: [Coedge(edgeID: edge.id, orientation: reversed ? .reversed : .forward,
                                           surfaceParameterCurve: .polyline(uv))])
        let sideUV = reversed
            ? [SurfaceParameter(u: 0, v: 0.01), SurfaceParameter(u: -0.03, v: 0.01)]
            : [SurfaceParameter(u: -0.03, v: 0.01), SurfaceParameter(u: 0, v: 0.01)]
        let sideLoop = Loop(edges: [Coedge(edgeID: changed.id, orientation: .reversed),
            Coedge(edgeID: edge.id, orientation: reversed ? .forward : .reversed, surfaceParameterCurve: .polyline(sideUV))])
        let changedLoop = Loop(edges: [Coedge(edgeID: changed.id)])
        let floorID = SurfaceID(), sideID = SurfaceID(), faceID = SurfaceID()
        let floor = Face(surfaceID: floorID, loops: [floorLoop.id])
        let side = Face(surfaceID: sideID, loops: [sideLoop.id])
        let face = Face(surfaceID: faceID, loops: [changedLoop.id])
        let shell = Shell(faceIDs: [floor.id, side.id, face.id])
        let body = Body(sheetShellIDs: [shell.id])
        var model = BRepModel(geometry: GeometryStore(curves: [oldID: oldCurve, changedID: changedCurve], surfaces: [
            floorID: .plane(Plane3D(origin: corner.point, normal: .unitZ)),
            sideID: .plane(Plane3D(origin: .origin, normal: .unitY)),
            faceID: .plane(Plane3D(origin: .origin, normal: .unitX))]),
            bodies: [body.id: body], shells: [shell.id: shell], faces: [floor.id: floor, side.id: side, face.id: face],
            loops: [floorLoop.id: floorLoop, sideLoop.id: sideLoop, changedLoop.id: changedLoop], edges: [edge.id: edge, changed.id: changed],
            vertices: [corner.id: corner, far.id: far, bottom.id: bottom])
        let lower = -0.005551361100027012
        try FaceSurfaceReplacementRebuilder().replace([face.id: .init(
            surface: .plane(Plane3D(origin: Point3D(x: lower, y: 0, z: 0), normal: .unitX)), orientation: .forward)],
            bodyID: body.id, featureID: FeatureID(), model: &model, tolerance: .standard,
            knownPoints: [corner.id: Point3D(x: lower, y: 0, z: 0.01), bottom.id: Point3D(x: lower, y: 0, z: 0)])
        let trim = try #require(model.edges[edge.id]?.trim)
        #expect(abs(trim.startParameter - lower) < 1e-12)
        #expect(trim.endParameter == 0.03)
        let chart = try #require(model.loops[floorLoop.id]?.coedges.first?.surfaceParameterCurve)
        let start = try chart.parameter(atNormalizedFraction: 0, tolerance: .standard)
        let end = try chart.parameter(atNormalizedFraction: 1, tolerance: .standard)
        #expect(abs(start.u - (reversed ? 0.03 : lower)) < 1e-12)
        #expect(abs(end.u - (reversed ? lower : 0.03)) < 1e-12)
        let sideChart = try #require(model.loops[sideLoop.id]?.coedges.last?.surfaceParameterCurve)
        let sideStart = try sideChart.parameter(atNormalizedFraction: 0, tolerance: .standard)
        let sideEnd = try sideChart.parameter(atNormalizedFraction: 1, tolerance: .standard)
        #expect(abs(sideStart.u - (reversed ? -lower : -0.03)) < 1e-12)
        #expect(abs(sideEnd.u - (reversed ? -0.03 : -lower)) < 1e-12)
        #expect(sideStart.v == 0.01 && sideEnd.v == 0.01)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledConstructionPublishesNoReceipt() async throws {
        let ready = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in ready.stream { break }
            return try construct()
        }
        task.cancel(); ready.continuation.yield(()); ready.continuation.finish()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
