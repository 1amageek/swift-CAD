import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Deforms a body from one face onto another (Deform Solid and Sheet). Every point of the body is
/// carried from its UVN coordinates on the reference face, through the options, to the same
/// coordinates on the target face.
///
/// The body keeps its topology and its trims: each face's support becomes a B-spline fitted to the
/// map of its old support over the face's own parameter box, so its trimming curves stay on it
/// unchanged, and each edge's curve becomes a B-spline fitted to the map of its old span on the
/// same parameters. Both fits stay within a quarter of the distance tolerance. A map that turns
/// the body inside out reverses every face; one that folds it is refused. The deformed faces are
/// sewn into a body beside the source, which the result replaces unless the feature keeps it.
struct WrapFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving

    init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try wrap(feature: feature, context: context)
        }
    }

    private func wrap(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .wrap(wrap) = feature.operation else {
            throw error(.invalidInput, feature.id, context, "Wrap evaluator requires a wrap feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try wrap.validate()
        }
        let tolerance = context.tolerance
        let sourceBodyID = try context.bodyID(generatedBy: wrap.target.featureID)
        guard let body = context.brep.bodies[sourceBodyID] else {
            throw error(.missingReference, feature.id, context, "Wrap target body is missing.")
        }
        let map = try WrapMap(wrap: wrap, context: context, resolver: resolver)

        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: sourceBodyID,
            featureID: feature.id,
            from: context.brep,
            sourceSubshapes: context.subshapes.entries,
            tolerance: tolerance
        )
        let samples = extraction.request.shells.flatMap(\.patches).flatMap(\.loops).flatMap(\.edges).map(\.startPoint)
        // A body reaching once around a closed target would meet itself across the seam: Plasticity
        // asks for the body or the surface to be split first.
        if try map.closesAroundTarget(at: samples) {
            throw error(.invalidInput, feature.id, context,
                        "Wrapped once around the closed target face, the body would meet itself; split the body or the face first.")
        }
        // The extractor names shell i of the body "shell:i" and its face j "shell:i:face:j", in
        // the body's own order, which is how a patch finds its face's parameter box.
        let deviation = tolerance.distance / 4
        let surfaceFitter = try MappedBSplineSurfaceFitter(deviation: deviation)
        let curveFitter = try SpatialCurveFitter(deviation: deviation)
        var edgeCurves: [EdgeSpan: BSplineCurve3D] = [:]
        func mappedEdge(_ edge: BRepSewingEdge) throws -> BRepSewingEdge {
            let span = EdgeSpan(curve: edge.curve, lower: min(edge.startParameter, edge.endParameter),
                                upper: max(edge.startParameter, edge.endParameter))
            let curve: BSplineCurve3D
            if let known = edgeCurves[span] {
                curve = known
            } else {
                curve = try curveFitter.fitBSpline(breakpoints: [span.lower, span.upper], tolerance: tolerance) { parameter in
                    try map.point(try span.curve.point(at: parameter, tolerance: tolerance))
                }.curve
                edgeCurves[span] = curve
            }
            return BRepSewingEdge(
                stableID: edge.stableID,
                curve: .bSpline(curve),
                startParameter: edge.startParameter,
                endParameter: edge.endParameter,
                startPoint: try curve.point(at: edge.startParameter, tolerance: tolerance),
                endPoint: try curve.point(at: edge.endParameter, tolerance: tolerance),
                surfaceParameterCurve: edge.surfaceParameterCurve,
                parentSubshapeIDs: edge.parentSubshapeIDs,
                startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs
            )
        }

        let bounds = FaceParameterExtentResolver()
        var shells: [BRepSewingShell] = []
        for (shellIndex, shell) in extraction.request.shells.enumerated() {
            guard shellIndex < body.shellIDs.count, let sourceShell = context.brep.shells[body.shellIDs[shellIndex]],
                  sourceShell.faceIDs.count == shell.patches.count else {
                throw error(.missingReference, feature.id, context, "Wrap lost the order of the target's faces.")
            }
            let patches = try zip(sourceShell.faceIDs, shell.patches).map { faceID, patch in
                let box = try bounds.bounds(for: faceID, in: context.brep, tolerance: tolerance)
                let surface = try surfaceFitter.fit(u: box.u, v: box.v, tolerance: tolerance) { u, v in
                    try map.point(try patch.surface.point(u: u, v: v, tolerance: tolerance))
                }.surface
                return BRepSewingFacePatch(
                    stableID: patch.stableID,
                    surface: .bSpline(surface),
                    orientation: patch.orientation,
                    loops: try patch.loops.map { loop in
                        BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map(mappedEdge))
                    },
                    parentSubshapeIDs: patch.parentSubshapeIDs
                )
            }
            shells.append(BRepSewingShell(stableID: shell.stableID, patches: patches, orientation: shell.orientation))
        }
        if try map.reversesOrientation(at: samples, featureID: feature.id) {
            let adapter = BRepSewingPatchOrientationAdapter()
            shells = try shells.map { shell in
                BRepSewingShell(
                    stableID: shell.stableID,
                    patches: try shell.patches.map { try adapter.reorient($0, to: $0.orientation == .forward ? .reversed : .forward, tolerance: tolerance) },
                    orientation: shell.orientation
                )
            }
        }
        let request = BRepSewingRequest(featureID: feature.id, bodyTopology: extraction.request.bodyTopology, shells: shells)
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)

        var model = context.brep
        var removedSubshapeIDs = Set<SubshapeID>()
        if !wrap.keepsTarget {
            let removal = BRepBodyTopologyRemoval()
            removedSubshapeIDs = removal.subshapeIDs(bodyID: sourceBodyID, in: model, subshapes: context.subshapes.entries)
            try removal.remove(bodyID: sourceBodyID, from: &model)
        }
        try BRepModelCombiner().merge(sewn.brep, into: &model)
        return EvaluationResult(brep: model, subshapes: sewn.subshapes, removedSubshapeIDs: removedSubshapeIDs, lineage: sewn.lineage)
    }

    private func error(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}

/// An edge's span of its curve, the unit its deformed curve is fitted and shared by.
private struct EdgeSpan: Hashable {
    let curve: Curve3D
    let lower: Double
    let upper: Double
}

/// The map Wrap carries points by: reference-face UVN coordinates, the options, target-face UVN
/// coordinates, each face read in its own body's frame and placed into the target's.
private struct WrapMap {
    private let reference: FaceUVNChart
    private let target: FaceUVNChart
    private let options: WrapOptions
    private let offsetN: Double
    /// Each face's body frame into the target's, and the reference's back out.
    private let fromReferenceFrame: RigidTransform3D?
    private let toTargetFrame: RigidTransform3D?
    private let tolerance: ModelingTolerance

    init(wrap: WrapFeature, context: EvaluationContext, resolver: ParameterResolving) throws {
        // The faces are resolved once; the charts then query them on every point. The two may
        // be one face.
        var references: [StableSubshapeReference: TopologyReference] = [:]
        for face in [wrap.referenceFace, wrap.targetFace] where references[face] == nil {
            references[face] = try context.topologyReference(for: face)
        }
        let faces = ResolvedFaceModel(brep: context.brep, references: references)
        reference = try FaceUVNChart(face: SurfaceReference(subshape: wrap.referenceFace), in: faces, tolerance: context.tolerance)
        target = try FaceUVNChart(face: SurfaceReference(subshape: wrap.targetFace), in: faces, tolerance: context.tolerance)
        let quantity = try resolver.evaluate(wrap.options.offsetN, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "wrap.offsetN", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: context.tolerance, message: "A Wrap N offset must be finite.")
        }
        for placement in [wrap.referencePlacement, wrap.targetPlacement].compactMap({ $0 }) {
            try placement.validate(tolerance: context.tolerance)
        }
        options = wrap.options
        offsetN = quantity.value
        fromReferenceFrame = wrap.referencePlacement?.inverted()
        toTargetFrame = wrap.targetPlacement
        tolerance = context.tolerance
    }

    func point(_ point: Point3D) throws -> Point3D {
        let coordinate = try reference.coordinate(of: fromReferenceFrame?.applying(to: point) ?? point)
        let mapped = options.mapped(s: coordinate.s, t: coordinate.t, n: coordinate.n, offsetN: offsetN)
        let placed = try target.point(at: UVNCoordinate(s: mapped.s, t: mapped.t, n: mapped.n))
        return toTargetFrame?.applying(to: placed) ?? placed
    }

    /// Whether the samples' images reach a whole turn or more around a periodic target face.
    func closesAroundTarget(at samples: [Point3D]) throws -> Bool {
        let mapped = try samples.map { point -> (s: Double, t: Double) in
            let coordinate = try reference.coordinate(of: fromReferenceFrame?.applying(to: point) ?? point)
            let image = options.mapped(s: coordinate.s, t: coordinate.t, n: coordinate.n, offsetN: offsetN)
            return (image.s, image.t)
        }
        guard let first = mapped.first else { return false }
        for alongS in [true, false] {
            guard let turn = target.periodSpan(alongS: alongS) else { continue }
            let values = mapped.map { alongS ? $0.s : $0.t }
            let reach = (values.max() ?? (alongS ? first.s : first.t)) - (values.min() ?? (alongS ? first.s : first.t))
            if reach >= turn * (1 - 1.0e-9) { return true }
        }
        return false
    }

    /// Whether the map turns space inside out at the samples, read from the sign of its
    /// Jacobian's determinant by central differences one thousandth of the samples' extent wide.
    /// A sign that changes across them, or a determinant too small to read, means the map folds
    /// or flattens the body there.
    func reversesOrientation(at samples: [Point3D], featureID: FeatureID) throws -> Bool {
        guard let first = samples.first else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                message: "A Wrap target has no vertices to read its orientation at.")
        }
        var lower = first, upper = first
        for sample in samples {
            lower = Point3D(x: min(lower.x, sample.x), y: min(lower.y, sample.y), z: min(lower.z, sample.z))
            upper = Point3D(x: max(upper.x, sample.x), y: max(upper.y, sample.y), z: max(upper.z, sample.z))
        }
        let step = (upper - lower).length * 1.0e-3
        guard step > tolerance.distance else {
            throw KernelError(phase: .evaluation, code: .invalidInput, featureID: featureID, tolerance: tolerance,
                message: "A Wrap target has no extent.")
        }
        var reverses: Bool?
        for sample in samples {
            func derivative(_ axis: Vector3D) throws -> Vector3D {
                (try point(sample + axis * step) - (try point(sample + axis * -step))) * (1 / (2 * step))
            }
            let columns = (try derivative(.unitX), try derivative(.unitY), try derivative(.unitZ))
            let determinant = columns.0.cross(columns.1).dot(columns.2)
            let scale = columns.0.length * columns.1.length * columns.2.length
            guard scale > 0, abs(determinant) > scale * 1.0e-6 else {
                throw KernelError(phase: .geometry, code: .singularGeometry, featureID: featureID, tolerance: tolerance,
                    message: "Wrap flattens the body: its map has no volume near a vertex.")
            }
            let here = determinant < 0
            if let reverses, reverses != here {
                throw KernelError(phase: .geometry, code: .singularGeometry, featureID: featureID, tolerance: tolerance,
                    message: "Wrap folds the body: its map turns space inside out at some vertices and not others.")
            }
            reverses = here
        }
        return reverses ?? false
    }
}

/// The model with Wrap's two faces already resolved, so the charts do not resolve them again for
/// every point they carry.
private struct ResolvedFaceModel: SurfaceQueryModel {
    let brep: BRepModel
    let references: [StableSubshapeReference: TopologyReference]

    func topologyReference(for reference: StableSubshapeReference) throws -> TopologyReference {
        guard let resolved = references[reference] else {
            throw KernelError(phase: .evaluation, code: .missingReference, tolerance: nil,
                message: "Wrap reads only its reference and target faces.")
        }
        return resolved
    }
}
