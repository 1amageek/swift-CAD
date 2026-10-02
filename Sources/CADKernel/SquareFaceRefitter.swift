import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Square's Refit of one face: its outer loop split into four sides at its four sharpest vertices
/// (every vertex of a four-edged loop), each side its edges' curves joined exactly, and the face's
/// new surface Square's fit of that frame with every side hard — G0, or tangent or curvature
/// continuous with the neighbouring face across it — so the face keeps its edges and vertices and
/// its coedges run along the new surface's boundary (constant-parameter trimming curves).
struct SquareFaceRefitter {
    struct Refit {
        let surface: BSplineSurface3D
        let orientation: Orientation
        /// The new trimming curve of each coedge of the face's loop, in the loop's order.
        let pcurves: [SurfaceParameterCurve]
    }

    let tolerance: ModelingTolerance

    func refit(_ faceID: FaceID, refit: SquareRefit, source: FeatureID, context: EvaluationContext, featureID: FeatureID) throws -> Refit {
        let model = context.brep
        guard let face = model.faces[faceID], let oldSurface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A face to refit is missing.")
        }
        guard face.loops.count == 1, let loop = model.loops[face.loops[0]] else {
            throw failure(.unsupportedCapability, featureID, "Square refits a face bounded by one loop, with no holes.")
        }
        let coedges = loop.coedges
        guard coedges.count >= 4 else {
            throw failure(.unsupportedCapability, featureID, "Square refits a face with at least four edges, split at its four sharpest corners.")
        }
        // Each coedge's curve, the parameters it runs between along the loop, and its tangents there.
        struct Run {
            let curve: Curve3D
            let start: Double
            let end: Double
            let startTangent: Vector3D
            let endTangent: Vector3D
        }
        let runs = try coedges.map { coedge -> Run in
            guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw failure(.missingReference, featureID, "An edge of a face to refit has no bounded curve.")
            }
            let (start, end) = coedge.orientation == .forward ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
            let sign = end >= start ? 1.0 : -1.0
            let startTangent = try (curve.differentialGeometry(at: start, tolerance: tolerance).firstDerivative * sign)
                .normalized(tolerance: tolerance.distance)
            let endTangent = try (curve.differentialGeometry(at: end, tolerance: tolerance).firstDerivative * sign)
                .normalized(tolerance: tolerance.distance)
            return Run(curve: curve, start: start, end: end, startTangent: startTangent, endTangent: endTangent)
        }
        // The corners: the four vertices where the loop turns most, each before coedge j.
        let turns = runs.indices.map { j in acos(min(1, max(-1, runs[(j + runs.count - 1) % runs.count].endTangent.dot(runs[j].startTangent)))) }
        let corners = runs.indices.sorted { turns[$0] > turns[$1] }.prefix(4).sorted()
        guard corners.count == 4 else {
            throw failure(.unsupportedCapability, featureID, "A face to refit has no four corners.")
        }
        let sides: [[Int]] = (0..<4).map { k in
            let from = corners[k], to = k == 3 ? corners[0] + runs.count : corners[k + 1]
            return (from..<to).map { $0 % runs.count }
        }
        // Each side its coedges' exact spans joined, running along the loop.
        let spanBuilder = ExactBSplineCurveSpanBuilder(tolerance: tolerance)
        let curves = try sides.map { side -> BSplineCurve3D in
            let spans = try side.flatMap { index -> [BSplineCurve3D] in
                let run = runs[index]
                let (lower, upper) = (min(run.start, run.end), max(run.start, run.end))
                let parameters = (0...32).map { lower + (upper - lower) * Double($0) / 32 }
                let section = EvaluatedCurve(sourceFeatureID: featureID, source: .generatedFeature, kind: .spline,
                                             points: try parameters.map { try run.curve.point(at: $0, tolerance: tolerance) },
                                             exactCurve: run.curve, exactParameterDomain: .closed(lower, upper),
                                             exactPointParameters: parameters)
                let forward = try spanBuilder.sectionSpans(from: section).map(\.curve)
                return run.end >= run.start ? forward : try forward.reversed().map { try $0.reversed(tolerance: tolerance) }
            }
            return spans.count == 1 ? spans[0] : try ExactCompositeBSplineCurveBuilder().build(spans: spans, tolerance: tolerance)
        }
        let frame = curves.enumerated().map { SquareFrameBuilder.Side(curve: $0.element, given: $0.offset) }
        let bodyID = try context.bodyID(generatedBy: source)
        let bodyRole: FeaturePort = model.bodies[bodyID]?.kind == .solid ? .body : .sheet
        let continuities = try sides.map { side -> SurfaceEdgeContinuity? in
            guard let order = refit.order else { return nil }
            // The side's edges border one neighbouring face, whose continuity the side takes.
            let neighbours = Set(side.map { index in
                model.faces.keys.filter { other in
                    other != faceID && (model.faces[other]?.loops ?? []).contains { loopID in
                        model.loops[loopID]?.coedges.contains { $0.edgeID == coedges[index].edgeID } ?? false
                    }
                }
            })
            // A side along the sheet's open boundary has no neighbour and stays G0.
            if neighbours == [[]] { return nil }
            guard neighbours.count == 1, let neighbour = neighbours.first, neighbour.count == 1 else {
                throw failure(.unsupportedCapability, featureID,
                              "A refit side continuous with its neighbour runs along edges of one neighbouring face.")
            }
            let edgeID = coedges[side[0]].edgeID
            guard let subshapeID = context.subshapes.entries.compactMap({ $0.value == .edge(edgeID) ? $0.key : nil }).sorted().first else {
                throw failure(.missingReference, featureID, "An edge of a face to refit has no identity.")
            }
            let reference = StableSubshapeReference(subshapeID: subshapeID, geometrySignature: try SubshapeGeometrySignatureBuilder(
                model: model, tolerance: tolerance).signature(for: .edge(edgeID)))
            return SurfaceEdgeContinuity(source: source, bodyRole: bodyRole, edge: reference, order: order, tension: 1,
                                         angularAllowance: refit.angularAllowance, curvatureAllowance: refit.curvatureAllowance)
        }
        let (exact, rotation) = try SquareSurfaceFeatureEvaluator.exactSheet(frame: frame, continuities: continuities,
                                                                             context: context, featureID: featureID)
        let boundaries = (0..<4).map { boundary -> SquareSurfaceFitter.Boundary in
            switch continuities[(boundary + rotation) % 4]?.order {
            case nil: .init(constraint: .hard(order: 0), flows: true)
            case .tangent?: .init(constraint: .hard(order: 1), flows: false)
            case .curvature?: .init(constraint: .hard(order: 2), flows: false)
            }
        }
        let surface = try SquareSurfaceFitter(tolerance: tolerance).fit(exact: exact, boundaries: boundaries, options: refit.options,
                                                                        featureID: featureID)
        // Each coedge's stretch of its side, by where its ends fall on the side's curve.
        var pcurves = Array(repeating: SurfaceParameterCurve.constantV(v: 0, uStart: 0, uEnd: 1), count: coedges.count)
        for (k, side) in sides.enumerated() {
            guard case let .closed(lower, upper) = curves[k].domain else {
                throw failure(.invalidInput, featureID, "A refit side has an unbounded domain.")
            }
            func fraction(_ point: Point3D) throws -> Double {
                let projected = try Curve3D.bSpline(curves[k]).parameterProjection(of: point, tolerance: tolerance).parameter
                return min(1, max(0, (projected - lower) / (upper - lower)))
            }
            let boundary = (k - rotation + 4) % 4
            for (position, index) in side.enumerated() {
                let run = runs[index]
                let a = position == 0 ? 0 : try fraction(try run.curve.point(at: run.start, tolerance: tolerance))
                let b = position == side.count - 1 ? 1 : try fraction(try run.curve.point(at: run.end, tolerance: tolerance))
                pcurves[index] = switch boundary {
                case 0: .constantV(v: 0, uStart: a, uEnd: b)
                case 1: .constantU(u: 1, vStart: a, vEnd: b)
                case 2: .constantV(v: 1, uStart: 1 - a, uEnd: 1 - b)
                default: .constantU(u: 0, vStart: 1 - a, vEnd: 1 - b)
                }
            }
        }
        // The face keeps facing the way it did: its new normal at the middle against the old one there.
        let middle = try surface.differentialGeometry(u: 0.5, v: 0.5, tolerance: tolerance)
        let projected = try oldSurface.parameterProjection(of: middle.position, tolerance: tolerance)
        let oldNormal = try oldSurface.normal(u: projected.u, v: projected.v, tolerance: tolerance) * (face.orientation == .forward ? 1 : -1)
        return Refit(surface: surface, orientation: middle.normal.dot(oldNormal) >= 0 ? .forward : .reversed, pcurves: pcurves)
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
