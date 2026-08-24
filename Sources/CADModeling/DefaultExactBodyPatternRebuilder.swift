import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct DefaultExactBodyPatternRebuilder: ExactBodyPatternRebuilding {
    private let sewer: any BRepSewing
    private let unionReducer: ExactPatternBodyUnionReducer

    package init(
        sewer: any BRepSewing,
        unionApplicator: any BooleanOperationApplying,
        separationValidator: any BodyJoinValidating
    ) {
        self.sewer = sewer
        self.unionReducer = ExactPatternBodyUnionReducer(
            applicator: unionApplicator,
            separationValidator: separationValidator
        )
    }

    package func rebuild(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard transforms.count >= 2 else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact pattern reconstruction requires at least two instances."
            )
        }
        let uniqueTransforms = uniqueTransformsPreservingOrder(transforms)
        var instances: [BRepSewingResult] = []
        instances.reserveCapacity(uniqueTransforms.count)
        for (index, transform) in uniqueTransforms.enumerated() {
            let request = try sewingRequest(
                featureID: uniqueTransforms.count == 1
                    ? featureID
                    : featureEvaluationStageID(
                        featureID: featureID,
                        domain: .patternInstance,
                        ordinal: UInt64(index)
                    ),
                bodyID: sourceBodyID,
                transforms: [transform],
                stablePrefix: "\(stablePrefix):instance:\(index)",
                context: context
            )
            instances.append(try sewer.sew(request, tolerance: context.tolerance))
        }
        let union: EvaluationResult
        if instances.count == 1, let instance = instances.first {
            union = EvaluationResult(
                brep: instance.brep,
                subshapes: instance.subshapes,
                lineage: instance.lineage
            )
        } else {
            union = try unionReducer.reduce(
                instances: instances,
                featureID: featureID,
                tolerance: context.tolerance
            )
        }
        let replacementBodyIDs = Set(union.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(bodyID) = reference else { return nil }
            return bodyID
        })
        guard replacementBodyIDs.count == 1, let replacementBodyID = replacementBodyIDs.first else {
            throw error(
                .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact pattern union did not publish exactly one replacement body."
            )
        }
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: sourceBodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: sourceBodyID,
            with: replacementBodyID,
            from: union.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: union.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: union.lineage
        )
    }

    private func sewingRequest(
        featureID: FeatureID,
        bodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let sourceComponents = body.solidComponents else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact pattern body input must resolve to exact solid topology."
            )
        }
        var sewingShells: [BRepSewingShell] = []
        for (instanceIndex, transform) in transforms.enumerated() {
            for (shellIndex, shellID) in body.shellIDs.enumerated() {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Exact pattern shell is missing.")
                }
                let patches = try shell.faceIDs.enumerated().map { faceIndex, faceID in
                    try patch(
                        stableID: "\(stablePrefix):instance:\(instanceIndex):shell:\(shellIndex):face:\(faceIndex)",
                        faceID: faceID,
                        transform: transform,
                        model: model,
                        context: context
                    )
                }
                sewingShells.append(BRepSewingShell(
                    stableID: shellStableID(
                        prefix: stablePrefix,
                        instanceIndex: instanceIndex,
                        shellIndex: shellIndex
                    ),
                    patches: patches,
                    orientation: shell.orientation
                ))
            }
        }
        let shellIndices = Dictionary(uniqueKeysWithValues: body.shellIDs.enumerated().map {
            ($0.element, $0.offset)
        })
        let components = try transforms.indices.flatMap { instanceIndex in
            try sourceComponents.map { component in
                guard let outerIndex = shellIndices[component.outerShellID] else {
                    throw TopologyError.missingReference(
                        "Exact pattern outer-shell ownership is missing."
                    )
                }
                let voidIndices = try component.voidShellIDs.map { shellID in
                    guard let index = shellIndices[shellID] else {
                        throw TopologyError.missingReference(
                            "Exact pattern void-shell ownership is missing."
                        )
                    }
                    return index
                }
                return BRepSewingSolidComponent(
                    outerShellStableID: shellStableID(
                        prefix: stablePrefix,
                        instanceIndex: instanceIndex,
                        shellIndex: outerIndex
                    ),
                    voidShellStableIDs: voidIndices.map {
                        shellStableID(
                            prefix: stablePrefix,
                            instanceIndex: instanceIndex,
                            shellIndex: $0
                        )
                    }
                )
            }
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyTopology: .solid(components: components),
            shells: sewingShells,
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func shellStableID(
        prefix: String,
        instanceIndex: Int,
        shellIndex: Int
    ) -> String {
        "\(prefix):instance:\(instanceIndex):shell:\(shellIndex)"
    }

    private func patch(
        stableID: String,
        faceID: FaceID,
        transform: ExactPatternTransform,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        guard let face = model.faces[faceID],
              let sourceSurface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Exact pattern face surface is missing.")
        }
        let surfaceImage = try ExactPatternSurfaceImage(
            source: sourceSurface,
            transform: transform,
            tolerance: context.tolerance
        )
        let surface = surfaceImage.surface
        let orientation = surfaceImage.reversesFaceOrientation
            ? reversed(face.orientation)
            : face.orientation
        let loops = try face.loops.enumerated().map { loopIndex, loopID in
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Exact pattern loop is missing.")
            }
            let edges = try loop.coedges.enumerated().map { edgeIndex, coedge in
                try transformedEdge(
                    stableID: "\(stableID):loop:\(loopIndex):edge:\(edgeIndex)",
                    coedge: coedge,
                    surfaceImage: surfaceImage,
                    transform: transform,
                    model: model,
                    context: context
                )
            }
            return BRepSewingLoop(
                stableID: "\(stableID):loop:\(loopIndex)",
                role: loop.role,
                edges: edges
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: loops,
            parentSubshapeIDs: subshapeIDs(for: .face(faceID), context: context)
        )
    }

    private func transformedEdge(
        stableID: String,
        coedge: Coedge,
        surfaceImage: ExactPatternSurfaceImage,
        transform: ExactPatternTransform,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingEdge {
        guard let sourceEdge = model.edges[coedge.edgeID],
              let sourceCurve = model.geometry.curves[sourceEdge.curveID],
              let storedStart = model.vertices[sourceEdge.startVertexID]?.point,
              let storedEnd = model.vertices[sourceEdge.endVertexID]?.point else {
            throw TopologyError.missingReference("Exact pattern edge geometry is missing.")
        }
        let isForward = coedge.orientation == .forward
        let sourceStartID = isForward
            ? sourceEdge.startVertexID
            : sourceEdge.endVertexID
        let sourceEndID = isForward
            ? sourceEdge.endVertexID
            : sourceEdge.startVertexID
        let start = transform.applying(to: isForward ? storedStart : storedEnd)
        let end = transform.applying(to: isForward ? storedEnd : storedStart)

        guard let parameterCurve = coedge.surfaceParameterCurve,
              let trim = sourceEdge.trim else {
            throw error(
                .topologyFailure,
                tolerance: context.tolerance,
                "Exact pattern source edge is missing its mandatory trim or pcurve."
            )
        }
        let startParameter = isForward
            ? trim.startParameter
            : trim.endParameter
        let endParameter = isForward
            ? trim.endParameter
            : trim.startParameter
        let targetParameterCurve = try surfaceImage.applying(
            to: parameterCurve,
            tolerance: context.tolerance
        )
        let targetCurve: Curve3D
        if case .rigidImage = targetParameterCurve {
            targetCurve = .rigidImage(try RigidImageCurve3D(
                source: sourceCurve,
                transform: transform,
                tolerance: context.tolerance
            ))
        } else {
            targetCurve = try transform.applying(
                to: sourceCurve,
                from: startParameter,
                to: endParameter,
                tolerance: context.tolerance
            )
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: targetCurve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: targetParameterCurve,
            parentSubshapeIDs: subshapeIDs(for: .edge(sourceEdge.id), context: context),
            startVertexParentSubshapeIDs: subshapeIDs(for: .vertex(sourceStartID), context: context),
            endVertexParentSubshapeIDs: subshapeIDs(for: .vertex(sourceEndID), context: context)
        )
    }

    private func reversed(_ orientation: Orientation) -> Orientation {
        orientation == .forward ? .reversed : .forward
    }

    private func uniqueTransformsPreservingOrder(
        _ transforms: [ExactPatternTransform]
    ) -> [ExactPatternTransform] {
        var seen = Set<ExactPatternTransform>()
        return transforms.filter { seen.insert($0).inserted }
    }

    private func subshapeIDs(
        for reference: TopologyReference,
        context: EvaluationContext
    ) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

}
