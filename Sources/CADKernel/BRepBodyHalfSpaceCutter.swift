import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Cuts a body at a plane by intersecting it with a box that covers the body's kept side, whose
/// top face lies on the plane.
struct BRepBodyHalfSpaceCutter: BodyHalfSpaceCutting {
    private let sewer: any BRepSewing
    private let applicator: any BooleanOperationApplying

    init(sewer: any BRepSewing, applicator: any BooleanOperationApplying) {
        self.sewer = sewer
        self.applicator = applicator
    }

    func cut(
        bodyID: BodyID,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult? {
        let tolerance = context.tolerance
        let normal = try planeNormal.normalized(tolerance: tolerance.distance)
        let bounds = try BRepBodyBoundingBoxBuilder().bounds(for: bodyID, in: context.brep, tolerance: tolerance)
        let low = bounds.minimum, high = bounds.maximum
        let corners = [low.x, high.x].flatMap { x in [low.y, high.y].flatMap { y in [low.z, high.z].map { z in
            Point3D(x: x, y: y, z: z)
        } } }
        let distances = corners.map { ($0 - planeOrigin).dot(normal) }
        guard let highest = distances.max(), let lowest = distances.min() else {
            throw error(.topologyFailure, featureID: featureID, tolerance: tolerance, "A plane cut needs the body's bounds.")
        }
        if highest <= tolerance.distance {
            return nil
        }
        guard lowest < -tolerance.distance else {
            throw error(.invalidInput, featureID: featureID, tolerance: tolerance,
                        "A plane cut keeps no material: the body lies entirely on the discarded side.")
        }
        // The body's bounds fit inside a square of half-width `diagonal` around its center projected
        // onto the plane, and reach at most `diagonal` below the plane.
        let diagonal = bounds.size.length
        let center = bounds.center
        let onPlane = center + normal * -((center - planeOrigin).dot(normal))
        let seed: Vector3D = abs(normal.x) < 0.9 ? .unitX : .unitY
        let x = try normal.cross(seed).normalized(tolerance: tolerance.distance)
        let y = (normal * -1).cross(x)
        let side = diagonal * 2
        let height = diagonal * 1.5
        let placement = PrimitivePlacement(origin: onPlane + x * -diagonal + y * -diagonal, axis: normal * -1, referenceDirection: x)
        let length = CADExpression.constant(.length(side, unit: .meter))
        let toolFeatureID = featureEvaluationStageID(featureID: featureID, domain: .mirrorCutTool, ordinal: 0)
        let request = try PrimitiveBRepRequestBuilder(tolerance: tolerance).box(
            BoxPrimitive(placement: placement, width: length, depth: length,
                         height: .constant(.length(height, unit: .meter))),
            width: side, depth: side, height: height, featureID: toolFeatureID
        )
        let tool = try sewer.sew(request, tolerance: tolerance)
        let toolBodyIDs = Set(tool.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(id) = reference else { return nil }
            return id
        })
        guard toolBodyIDs.count == 1, let toolBodyID = toolBodyIDs.first else {
            throw error(.topologyFailure, featureID: featureID, tolerance: tolerance, "A plane cut tool is not one body.")
        }
        let model = try BRepModelCombiner().combined([context.brep, tool.brep])
        var subshapes = context.subshapes.entries
        subshapes.merge(tool.subshapes) { current, _ in current }
        var lineage = context.lineage
        lineage.merge(tool.lineage) { current, _ in current }
        if context.brep.bodies[bodyID]?.kind == .sheet {
            return try BRepSheetHalfSpaceCutter(sewer: sewer).cut(
                bodyID: bodyID, toolBodyID: toolBodyID, planeOrigin: planeOrigin,
                planeNormal: normal, featureID: featureID, model: model,
                context: context
            )
        }
        var result = try applicator.apply(
            operation: .intersect,
            targetBodyIDs: [bodyID],
            toolBodyID: toolBodyID,
            keepTools: false,
            featureID: featureID,
            model: model,
            subshapes: subshapes,
            toolSubshapes: tool.subshapes,
            inputLineage: lineage,
            tolerance: tolerance
        )
        // The tool box was never published, so its identities are neither removed nor parents.
        let toolSubshapeIDs = Set(tool.subshapes.keys)
        result.removedSubshapeIDs.subtract(toolSubshapeIDs)
        result.lineage = result.lineage.mapValues { entry in
            TopologyLineage(
                output: entry.output,
                parents: entry.parents.filter { !toolSubshapeIDs.contains($0) },
                relation: entry.relation
            )
        }.withRelationsDerivedFromParents()
        return result
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
