import CADCore
@testable import CADGeometry
@testable import CADTopology
import Foundation
import Testing

@Suite("Original C0 ruled surface area")
struct RuledSurfaceAreaIntegrationTests {
    private let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-6)
    private let knot = 0.37

    private func support(weighted: Bool) -> Surface3D {
        func rail(y: Double) -> Curve3D {
            .bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, knot, 1, 1],
                controlPoints: [Point3D(x: 0, y: y, z: 0),
                    Point3D(x: 0.0074, y: y, z: 0), Point3D(x: 0.02, y: y, z: 0.02)],
                weights: weighted ? [1, 2, 1] : [1, 1, 1]))
        }
        return .procedural(.ruled(RuledSurface3D(startBoundary: rail(y: 0), endBoundary: rail(y: 0.03))))
    }

    private func rectangle(_ u0: Double = 0, _ u1: Double = 1,
                           _ v0: Double = 0, _ v1: Double = 1) -> [SurfaceParameterCurve] {
        [.constantV(v: v0, uStart: u0, uEnd: u1),
         .constantU(u: u1, vStart: v0, vEnd: v1),
         .constantV(v: v1, uStart: u1, uEnd: u0),
         .constantU(u: u0, vStart: v1, vEnd: v0)]
    }

    private func fixture(_ surface: Surface3D, hole: Bool = false,
                         reversed: Bool = false,
                         mapping: (source: Surface3D, transform: RigidTransform3D)? = nil) throws -> (FaceID, BRepModel) {
        let surfaceID = SurfaceID()
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]))
        var boundaries = [rectangle()]
        if hole { boundaries.append(rectangle(knot / 2, (1 + knot) / 2, 0.25, 0.75)) }
        if let mapping {
            boundaries = try boundaries.map { curves in
                try curves.map { curve in
                    .rigidImage(try RigidImageSurfaceParameterCurve(
                        source: SurfaceLiftCurve3D(surface: mapping.source, parameterCurve: curve),
                        targetSurface: surface, transform: mapping.transform, tolerance: tolerance))
                }
            }
        }
        var loopIDs: [LoopID] = []
        for (index, original) in boundaries.enumerated() {
            let curves = reversed ? try original.reversed().map { try $0.reversed(tolerance: tolerance) } : original
            let vertices = try curves.map { curve -> Vertex in
                let uv = try curve.parameter(atNormalizedFraction: 0, tolerance: tolerance)
                return Vertex(point: try surface.point(u: uv.u, v: uv.v, tolerance: tolerance))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            var coedges: [Coedge] = []
            for i in curves.indices {
                let curveID = CurveID()
                model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(
                    surface: surface, parameterCurve: curves[i]))
                let edge = Edge(curveID: curveID, startVertexID: vertices[i].id,
                    endVertexID: vertices[(i + 1) % vertices.count].id,
                    trim: CurveTrim(startParameter: 0, endParameter: 1))
                model.edges[edge.id] = edge
                coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: curves[i]))
            }
            let loop = Loop(role: index == 0 ? .outer : .inner, coedges: coedges)
            model.loops[loop.id] = loop
            loopIDs.append(loop.id)
        }
        let face = Face(surfaceID: surfaceID, loops: loopIDs,
            orientation: reversed ? .reversed : .forward)
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        try model.validatePcurves(tolerance: tolerance)
        return (face.id, model)
    }

    // The two physical planar strips give these integrals independently of
    // rational speed, source derivatives, decomposition and area quadrature.
    private func oracle(weighted: Bool, hole: Bool) -> (Double, Point3D) {
        let first = 0.03 * 0.0074
        let second = 0.03 * sqrt(0.0126 * 0.0126 + 0.02 * 0.02)
        let removedFirst = hole ? first / (weighted ? 6 : 4) : 0
        let removedSecond = hole ? second / (weighted ? 6 : 4) : 0
        let area = first + second - removedFirst - removedSecond
        let holeFirstX = weighted ? 5 * 0.0074 / 6 : 0.75 * 0.0074
        let holeSecondX = 0.0074 + 0.0126 / (weighted ? 6 : 4)
        let holeSecondZ = 0.02 / (weighted ? 6 : 4)
        return (area, Point3D(
            x: (first * 0.0037 + second * 0.0137 - removedFirst * holeFirstX
                - removedSecond * holeSecondX) / area,
            y: 0.015, z: (second * 0.01 - removedSecond * holeSecondZ) / area))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalFoldedRuledRectangleHasIndependentAreaAndXYZCentroid(_ weighted: Bool) throws {
        for reversed in [false, true] {
            let (id, model) = try fixture(support(weighted: weighted), reversed: reversed)
            let original = model
            let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
            let (area, centroid) = oracle(weighted: weighted, hole: false)
            #expect(abs(result.area - area) <= tolerance.distance * tolerance.distance + tolerance.relative * area)
            #expect((result.centroid - centroid).length <= tolerance.distance)
            #expect(model == original)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalFoldedRuledHoleAndReversalRetainAllMoments(_ weighted: Bool) throws {
        for reversed in [false, true] {
            let (id, model) = try fixture(support(weighted: weighted), hole: true, reversed: reversed)
            let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
            let (area, centroid) = oracle(weighted: weighted, hole: true)
            #expect(abs(result.area - area) <= tolerance.distance * tolerance.distance + tolerance.relative * area)
            #expect((result.centroid - centroid).length <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalFoldedRuledRigidImageRetainsMappedTrimsAndXYZCentroid(_ reversed: Bool) throws {
        let source = support(weighted: true)
        let transform = try RigidTransform3D(basisX: Vector3D(x: 0, y: 1, z: 0),
            basisY: Vector3D(x: -1, y: 0, z: 0), basisZ: .unitZ,
            translation: Vector3D(x: 0.125, y: 0.25, z: 0.5), tolerance: tolerance)
        let target = try transform.applying(to: source, tolerance: tolerance)
        let (id, model) = try fixture(target, hole: true, reversed: reversed,
            mapping: (source, transform))
        let result = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
        let (area, centroid) = oracle(weighted: true, hole: true)
        let image = Point3D(x: 0.125 - centroid.y, y: 0.25 + centroid.x, z: 0.5 + centroid.z)
        #expect(abs(result.area - area) <= tolerance.distance * tolerance.distance + tolerance.relative * area)
        #expect((result.centroid - image).length <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalFoldedRuledNativeSpansRetainOneSidedFieldsAndCrossFoldValueProof(_ weighted: Bool) throws {
        let source = support(weighted: weighted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface: source, tolerance: tolerance)
        #expect(prepared.surface == source)
        #expect(prepared.hasNativeDensityJumps)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0, upper: 1))
        let optionalDomains = try prepared.nativeRectangleDomains(over: box, maximumCount: 2, tolerance: tolerance)
        let domains = try #require(optionalDomains)
        #expect(domains.count == 2)
        let full = try prepared.rectangularTranslationBounds(rectangle: box,
            fraction: ScalarInterval(lower: 0, upper: 1), reference: .origin, tolerance: tolerance)
        #expect(full.allSatisfy { $0.derivativeU == nil && $0.secondUU == nil })
        for (index, domain) in domains.enumerated() {
            let fields = try prepared.rectangularTranslationBounds(rectangle: domain.rectangle,
                fraction: ScalarInterval(lower: 0.5, upper: 0.5), reference: .origin,
                tolerance: tolerance, domain: domain)
            let length = index == 0 ? 0.0074 : sqrt(0.0126 * 0.0126 + 0.02 * 0.02)
            let speed = weighted ? 8.0 / 9 : 1
            let density = 0.03 * length * speed
            let x = index == 0 ? (weighted ? 2 * 0.0074 / 3 : 0.0037)
                : (weighted ? 0.0074 + 0.0126 / 3 : 0.0137)
            let z = index == 0 ? 0 : (weighted ? 0.02 / 3 : 0.01)
            let values: [Double] = [density, density * x, density * 0.015, density * z]
            for (field, value) in zip(fields, values) {
                #expect(field.value.contains(value))
                #expect(field.derivativeU != nil && field.secondUU != nil)
            }
        }
        // Equal physical strip images do not transfer native knot/weight ownership.
        let foreign = try PreparedSurfaceAreaIntegrand(surface: support(weighted: !weighted), tolerance: tolerance)
        do {
            _ = try foreign.rectangularTranslationBounds(rectangle: domains[0].rectangle,
                fraction: ScalarInterval(lower: 0.5, upper: 0.5), reference: .origin,
                tolerance: tolerance, domain: domains[0])
            Issue.record("A native ruled span was accepted by another original denominator owner.")
        } catch let error as KernelError { #expect(error.code == .invalidInput) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalRuledRectangleIntegralContainsIndependentPartialFourFields(_ weighted: Bool) throws {
        let source = support(weighted: weighted)
        let prepared = try PreparedSurfaceAreaIntegrand(surface: source, tolerance: tolerance)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0.25, upper: 0.75))
        let optionalDomains = try prepared.nativeRectangleDomains(over: box, maximumCount: 2, tolerance: tolerance)
        let domains = try #require(optionalDomains)
        let reference = Point3D(x: 0.003, y: -0.004, z: 0.005)
        for (index, domain) in domains.enumerated() {
            let optional = try prepared.originalRuledRectangleIntegral(rectangle: domain.rectangle,
                fraction: ScalarInterval(lower: 0.25, upper: 0.75), reference: reference,
                tolerance: tolerance, domain: domain)
            let fields = try #require(optional)
            let length = index == 0 ? 0.0074 : sqrt(0.0126 * 0.0126 + 0.02 * 0.02)
            // Original weights (1,2) and (2,1) yield h differences 16/35;
            // their means are 22/35 and 13/35, independently of native knot width.
            let measure = weighted ? 16.0 / 35 : 0.5
            let mean = weighted ? (index == 0 ? 22.0 / 35 : 13.0 / 35) : 0.5
            let area = length * 0.03 * measure * 0.5
            let x = index == 0 ? 0.0074 * mean : 0.0074 + 0.0126 * mean
            let z = index == 0 ? 0 : 0.02 * mean
            let literal: [Double] = [area, area * (x - 0.003), area * 0.019, area * (z - 0.005)]
            #expect(fields.count == 4)
            for (field, value) in zip(fields, literal) {
                #expect(field.contains(value))
                #expect(field.width <= 64 * Double.ulpOfOne * max(1, abs(value)))
            }
            do {
                _ = try prepared.originalRuledRectangleIntegral(rectangle: domain.rectangle,
                    fraction: ScalarInterval(lower: -0.125, upper: 0.5), reference: reference,
                    tolerance: tolerance, domain: domain)
                Issue.record("An outside fraction acquired original rectangle authority.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
            do {
                _ = try prepared.originalRuledRectangleIntegral(rectangle: domain.rectangle,
                    fraction: ScalarInterval(lower: 0, upper: 1), reference: reference,
                    tolerance: ModelingTolerance(distance: 2e-6, angle: 1e-9, relative: 1e-6), domain: domain)
                Issue.record("A different preparation tolerance acquired original rectangle authority.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
            let foreign = SurfaceAreaNativeSpanDomain(rectangle: domain.rectangle, radialRange: nil,
                index: 1 - domain.index, source: domain.source, curve: nil, anchor: nil)
            do {
                _ = try prepared.originalRuledRectangleIntegral(rectangle: domain.rectangle,
                    fraction: ScalarInterval(lower: 0, upper: 1), reference: reference,
                    tolerance: tolerance, domain: foreign)
                Issue.record("Another native owning side acquired original rectangle authority.")
            } catch let error as KernelError { #expect(error.code == .invalidInput) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalRuledInteriorTranslationPerturbationCannotAcquireRectangleIntegral() throws {
        guard case .procedural(.ruled(let original)) = support(weighted: true),
              case .bSpline(var end) = original.endBoundary else {
            Issue.record("The independent fixture lost its original rational rails.")
            return
        }
        let control = end.controlPoints[1]
        end.controlPoints[1] = Point3D(x: control.x, y: control.y.nextUp, z: control.z)
        let source = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: original.startBoundary, endBoundary: .bSpline(end))))
        let prepared = try PreparedSurfaceAreaIntegrand(surface: source, tolerance: tolerance)
        #expect(prepared.surface == source)
        let box = SurfaceParameterBox(u: try ScalarInterval(lower: 0, upper: 1),
            v: try ScalarInterval(lower: 0, upper: 1))
        let optional = try prepared.nativeRectangleDomains(over: box, maximumCount: 2, tolerance: tolerance)
        let domains = try #require(optional)
        for domain in domains {
            let integral = try prepared.originalRuledRectangleIntegral(rectangle: domain.rectangle,
                fraction: ScalarInterval(lower: 0, upper: 1), reference: .origin,
                tolerance: tolerance, domain: domain)
            #expect(integral == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unmatchedOriginalRuledDenominatorsRemainAnExplicitIncompleteFamily() throws {
        guard case .procedural(.ruled(let original)) = support(weighted: true),
              case .bSpline(var end) = original.endBoundary else {
            Issue.record("The independent fixture lost its original rational rails.")
            return
        }
        end.weights = [1, 3, 1]
        let source = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: original.startBoundary, endBoundary: .bSpline(end))))
        let (id, model) = try fixture(source)
        do {
            _ = try model.faceAreaMeasurement(of: id, tolerance: tolerance)
            Issue.record("Unequal original denominators were treated as one structurally identical tensor.")
        } catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalFoldedRuledUsesOneWorkBudgetForBothSpansAndHole() throws {
        let (id, model) = try fixture(support(weighted: false), hole: true)
        do {
            _ = try model.faceAreaMeasurement(of: id, tolerance: tolerance,
                integrationOptions: FaceAreaIntegrationOptions(maximumCellCount: 3))
            Issue.record("The ruled native pieces ignored the shared query work limit.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
        do {
            // The two original rail nets fit, but their eight native tensor
            // span controls must fit the same preparation ceiling as a spline.
            _ = try model.faceAreaMeasurement(of: id, tolerance: tolerance,
                integrationOptions: FaceAreaIntegrationOptions(maximumControlPointCount: 6))
            Issue.record("Ruled tensor preparation ignored its original control admission limit.")
        } catch let error as KernelError { #expect(error.code == .resourceLimitExceeded) }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalFoldedRuledCancellationDoesNotPublishMeasurement() async throws {
        let (id, model) = try fixture(support(weighted: true), hole: true)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try model.faceAreaMeasurement(of: id, tolerance: tolerance)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled ruled integration published a measurement.")
        } catch is CancellationError {
        } catch let error as KernelError {
            #expect(error.code == .cancelled)
        }
    }
}
