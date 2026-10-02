import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Square's Analysis: each given side measured on the evaluated sheet. The side's boundary is the
/// sheet boundary nearest its curve; G0 is the largest distance from the curve to it, sampled at
/// 33 points and projected onto the boundary. A side continuous with a face beside its edge is
/// measured against the bordering face that meets it best: the largest angle between the normals
/// (G1) and, at curvature order, the largest difference of the normal curvatures across the side
/// (G2), at 32 interior points. A planar face's exact continuity is judged against 10⁻⁶ rad and
/// 10⁻³ m⁻¹ (sampling noise), a curved face's against its allowances, positions against the
/// modeling distance.
public struct SquareSideAnalyzer {
    public init() {}

    public func analyze(_ featureID: FeatureID, in document: EvaluatedDocument) throws -> [SquareSideAnalysis] {
        let tolerance = document.configuration.tolerance
        guard let node = document.document.designGraph.nodes[featureID], case let .squareSurface(square) = node.operation else {
            throw refusal("Analysis takes a Square feature.", featureID, tolerance)
        }
        guard let sheet = document.subshapes.entries.compactMap({ key, value -> Surface3D? in
            guard key.featureID == featureID, case let .face(id) = value, let face = document.brep.faces[id] else { return nil }
            return document.brep.geometry.surfaces[face.surfaceID]
        }).first, case let .closed(u0, u1) = sheet.uDomain, case let .closed(v0, v1) = sheet.vDomain else {
            throw refusal("The Square has no evaluated sheet to analyze.", featureID, tolerance)
        }
        let curves = try SquareSurfaceFeatureEvaluator.sideCurves(of: square, curves: document.curves, tolerance: tolerance, featureID: featureID)
        // The sheet's boundaries v = v0, u = u1, v = v1, u = u0 as (u, v) of a parameter along them.
        let boundaries: [(Double) -> (Double, Double)] = [{ ($0, v0) }, { (u1, $0) }, { ($0, v1) }, { (u0, $0) }]
        let ranges = [(u0, u1), (v0, v1), (u0, u1), (v0, v1)]
        func nearest(_ point: Point3D, on boundary: Int) throws -> (u: Double, v: Double, distance: Double) {
            let (low, high) = ranges[boundary]
            func distance(_ s: Double) throws -> Double {
                let (u, v) = boundaries[boundary](s)
                return (try sheet.point(u: u, v: v, tolerance: tolerance) - point).length
            }
            let steps = 128
            var best = (s: low, d: try distance(low))
            for k in 1...steps {
                let s = low + (high - low) * Double(k) / Double(steps)
                let d = try distance(s)
                if d < best.d { best = (s, d) }
            }
            var a = max(low, best.s - (high - low) / Double(steps)), b = min(high, best.s + (high - low) / Double(steps))
            let ratio = (5.0.squareRoot() - 1) / 2
            for _ in 0..<80 {
                let c = b - ratio * (b - a), d = a + ratio * (b - a)
                if try distance(c) < distance(d) { b = d } else { a = c }
            }
            let s = 0.5 * (a + b)
            let (u, v) = boundaries[boundary](s)
            return (u, v, min(best.d, try distance(s)))
        }
        return try square.sides.indices.map { index in
            let curve = curves[index]
            guard case let .closed(t0, t1) = curve.domain else {
                throw refusal("A Square's side has an unbounded domain.", featureID, tolerance)
            }
            let points = try (0...32).map { try Curve3D.bSpline(curve).point(at: t0 + (t1 - t0) * Double($0) / 32, tolerance: tolerance) }
            var side = (boundary: 0, position: Double.infinity)
            for boundary in 0..<4 {
                let position = try points.map { try nearest($0, on: boundary).distance }.max() ?? .infinity
                if position < side.position { side = (boundary, position) }
            }
            guard let continuity = square.sides[index].continuity else {
                return SquareSideAnalysis(side: index, position: side.position, positionLimit: tolerance.distance)
            }
            let faces = try bordering(continuity, in: document, featureID: featureID, tolerance: tolerance)
            let curvatureOrder = continuity.order == .curvature
            var best: (angle: Double, curvature: Double)?
            for face in faces {
                var angle = 0.0, curvature = 0.0
                for k in 0..<32 {
                    let point = try Curve3D.bSpline(curve).point(at: t0 + (t1 - t0) * (Double(k) + 0.5) / 32, tolerance: tolerance)
                    let (u, v, _) = try nearest(point, on: side.boundary)
                    let jet = try sheet.differentialGeometry(u: u, v: v, tolerance: tolerance)
                    let projected = try face.parameterProjection(of: jet.position, tolerance: tolerance)
                    let faceJet = try face.differentialGeometry(u: projected.u, v: projected.v, tolerance: tolerance)
                    let aligned = faceJet.normal.dot(jet.normal) < 0 ? -1.0 : 1.0
                    angle = max(angle, acos(min(1, abs(jet.normal.dot(faceJet.normal)))))
                    guard curvatureOrder else { continue }
                    // Across the side: the sheet's tangent perpendicular to the boundary.
                    let along = side.boundary % 2 == 0 ? jet.tangentU : jet.tangentV
                    let across = try jet.normal.cross(along).normalized(tolerance: tolerance.distance)
                    let sheetCurvature = try normalCurvature(jet.tangentU, jet.tangentV, jet.secondDerivativeUU, jet.secondDerivativeUV,
                                                             jet.secondDerivativeVV, normal: jet.normal, direction: across)
                    let faceCurvature = try normalCurvature(faceJet.tangentU, faceJet.tangentV, faceJet.secondDerivativeUU,
                                                            faceJet.secondDerivativeUV, faceJet.secondDerivativeVV,
                                                            normal: faceJet.normal * aligned, direction: across)
                    curvature = max(curvature, abs(sheetCurvature - faceCurvature))
                }
                if best.map({ angle < $0.angle }) ?? true { best = (angle, curvature) }
            }
            guard let best else {
                throw refusal("A continuous side's edge borders no face.", featureID, tolerance)
            }
            return SquareSideAnalysis(
                side: index, position: side.position, positionLimit: tolerance.distance,
                angle: best.angle, angleLimit: continuity.angularAllowance ?? 1e-6,
                curvature: curvatureOrder ? best.curvature : nil,
                curvatureLimit: curvatureOrder ? (continuity.curvatureAllowance ?? 1e-3) : nil
            )
        }
    }

    /// The surfaces of the faces bordering a continuity's edge.
    private func bordering(_ continuity: SurfaceEdgeContinuity, in document: EvaluatedDocument, featureID: FeatureID,
                           tolerance: ModelingTolerance) throws -> [Surface3D] {
        let model = document.brep
        let resolved = try StableSubshapeResolver().topologyReference(for: continuity.edge, model: model, subshapes: document.subshapes,
                                                                     lineage: document.lineage, tolerance: tolerance)
        guard case let .edge(edgeID) = resolved else {
            throw refusal("A continuity edge did not resolve to an edge.", featureID, tolerance)
        }
        return model.faces.values.filter { face in
            face.loops.contains { model.loops[$0]?.coedges.contains { $0.edgeID == edgeID } ?? false }
        }.compactMap { model.geometry.surfaces[$0.surfaceID] }
    }

    /// The normal curvature II(D)/I(D) of a surface along the tangent direction nearest `direction`.
    private func normalCurvature(_ su: Vector3D, _ sv: Vector3D, _ suu: Vector3D, _ suv: Vector3D, _ svv: Vector3D,
                                 normal: Vector3D, direction: Vector3D) throws -> Double {
        let (e, f, g) = (su.dot(su), su.dot(sv), sv.dot(sv))
        let determinant = e * g - f * f
        guard determinant > 0 else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: nil, message: "A degenerate surface has no curvature.")
        }
        let (p, q) = (direction.dot(su), direction.dot(sv))
        let a = (g * p - f * q) / determinant, b = (e * q - f * p) / determinant
        let first = e * a * a + 2 * f * a * b + g * b * b
        let second = suu.dot(normal) * a * a + 2 * suv.dot(normal) * a * b + svv.dot(normal) * b * b
        return second / first
    }

    private func refusal(_ message: String, _ featureID: FeatureID, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance, message: message)
    }
}
