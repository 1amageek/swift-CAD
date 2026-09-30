import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Align Surface: the target sheet's one B-spline face, bounded by its surface's parameter lines,
/// has its chosen edge aligned to the reference edge (`BSplineSurfaceEdgeAligner`), a boundary
/// edge of a B-spline face placed in the target's frame, and the sheet is sewn anew on the
/// aligned surface in its place.
public struct SurfaceAlignFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let subshapeResolver: any StableSubshapeResolving

    public init(sewer: any BRepSewing = DefaultBRepSewer(), subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.sewer = sewer
        self.subshapeResolver = subshapeResolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateAlignment(feature: feature, context: context)
        }
    }

    private func evaluateAlignment(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .surfaceAlign(align) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Align Surface evaluator requires a surfaceAlign feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try align.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let model = context.brep
        let bodyID = try context.bodyID(generatedBy: align.target.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        let faces = scope.references.compactMap { reference -> FaceID? in
            guard case let .face(id) = reference else { return nil }
            return id
        }
        guard model.bodies[bodyID]?.kind == .sheet, faces.count == 1, let faceID = faces.first, let face = model.faces[faceID],
              case let .bSpline(targetSurface)? = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.unsupportedCapability, feature.id, tolerance, "Align Surface aligns a sheet of one B-spline face.")
        }
        let targetSide = try boundarySide(of: align.targetEdge, onFace: faceID, of: targetSurface, featureID: feature.id, context: context)
        // The reference edge on its B-spline face, placed in the target's frame.
        let referenceBodyID = try context.bodyID(generatedBy: align.reference.featureID)
        let referenceScope = try BodyTopologyScope(bodyID: referenceBodyID, model: model)
        let referenceEdge = try edgeID(align.referenceEdge, featureID: feature.id, context: context)
        var referenceFace: (id: FaceID, surface: BSplineSurface3D)?
        for case let .face(candidate) in referenceScope.references {
            guard let candidateFace = model.faces[candidate], case let .bSpline(surface)? = model.geometry.surfaces[candidateFace.surfaceID],
                  candidateFace.loops.contains(where: { model.loops[$0]?.coedges.contains { $0.edgeID == referenceEdge } == true }) else { continue }
            referenceFace = (candidate, surface)
            break
        }
        guard let referenceFace else {
            throw failure(.unsupportedCapability, feature.id, tolerance, "Align Surface aligns to an edge of a B-spline face.")
        }
        let referenceSide = try boundarySide(of: align.referenceEdge, onFace: referenceFace.id, of: referenceFace.surface, featureID: feature.id, context: context)
        var reference = referenceFace.surface
        if let placement = align.referencePlacement {
            guard case let .bSpline(placed) = try placement.applying(to: .bSpline(reference), tolerance: tolerance) else {
                throw failure(.topologyFailure, feature.id, tolerance, "A placed reference surface is no longer a B-spline surface.")
            }
            reference = placed
        }
        let continuity: Int = switch align.continuity {
        case .positional: 0
        case .tangentPlane: 1
        case .curvature: 2
        }
        let aligned = try BSplineSurfaceEdgeAligner().aligned(
            targetSurface, side: targetSide, to: reference, side: referenceSide,
            continuity: continuity, tension: align.tension, blendRows: align.blendRows,
            inputShapeInfluence: align.inputShapeInfluence, partialStart: align.partialStart, partialEnd: align.partialEnd,
            layout: align.layout.map {
                MappedBSplineSurfaceFitter.Layout(uDegree: $0.uDegree, vDegree: $0.vDegree, uSpans: $0.uSpans, vSpans: $0.vSpans)
            },
            tolerance: tolerance
        )
        // The sheet sewn anew on the aligned surface, bounded by its parameter lines.
        let parents = context.subshapeIDs(for: .face(faceID))
        let patch = try BSplineParameterRectanglePatchBuilder().patch(
            aligned, stableID: "surface-align:face", orientation: face.orientation, parentSubshapeIDs: parents, tolerance: tolerance
        )
        let sewn = try sewer.sew(
            BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: [BRepSewingShell(stableID: "surface-align:shell", patches: [patch])]),
            tolerance: tolerance
        )
        let replaced = try BRepBodyModelReplacer().replacing(bodyIDs: [bodyID], with: sewn.brep, in: model)
        try replaced.validate(level: .exact, tolerance: tolerance)
        return EvaluationResult(
            brep: replaced,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes)
                .union(context.subshapes.entries.filter { $0.value == .body(bodyID) }.map(\.key)),
            lineage: sewn.lineage
        )
    }

    private func edgeID(_ reference: StableSubshapeReference, featureID: FeatureID, context: EvaluationContext) throws -> EdgeID {
        let resolved = try subshapeResolver.topologyReference(
            for: reference, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = resolved else {
            throw KernelError(phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: reference.subshapeID,
                              tolerance: context.tolerance, message: "An Align Surface edge did not resolve to an edge.")
        }
        return edgeID
    }

    /// Which parameter boundary of its face's B-spline surface an edge runs along.
    private func boundarySide(
        of reference: StableSubshapeReference, onFace faceID: FaceID, of surface: BSplineSurface3D,
        featureID: FeatureID, context: EvaluationContext
    ) throws -> BSplineSurfaceBoundaryExtender.Side {
        let edgeID = try edgeID(reference, featureID: featureID, context: context)
        let tolerance = context.tolerance
        guard let face = context.brep.faces[faceID],
              let pcurve = face.loops.lazy.compactMap({ context.brep.loops[$0]?.coedges.first { $0.edgeID == edgeID }?.surfaceParameterCurve }).first,
              let u0 = surface.uKnots.first, let u1 = surface.uKnots.last, let v0 = surface.vKnots.first, let v1 = surface.vKnots.last else {
            throw failure(.missingReference, featureID, tolerance, "An Align Surface edge does not bound its face.")
        }
        switch pcurve {
        case let .constantU(u, _, _) where abs(u - u0) <= tolerance.distance: return .uLower
        case let .constantU(u, _, _) where abs(u - u1) <= tolerance.distance: return .uUpper
        case let .constantV(v, _, _) where abs(v - v0) <= tolerance.distance: return .vLower
        case let .constantV(v, _, _) where abs(v - v1) <= tolerance.distance: return .vUpper
        default:
            throw failure(.unsupportedCapability, featureID, tolerance, "Align Surface aligns edges along a B-spline surface's parameter boundaries.")
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
