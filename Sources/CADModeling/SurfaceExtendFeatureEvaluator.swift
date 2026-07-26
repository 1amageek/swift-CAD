import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceExtendFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let targetResolver: any SurfaceOperationTargetResolving
    private let boundsValidator: ExactSurfaceParameterBoundsValidator
    private let loopValidator: ExactSurfaceTrimLoopValidator
    private let sewer: any BRepSewing

    public init() {
        targetResolver = DefaultSurfaceOperationTargetResolver()
        boundsValidator = ExactSurfaceParameterBoundsValidator()
        loopValidator = ExactSurfaceTrimLoopValidator()
        sewer = DefaultBRepSewer()
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .surfaceExtend(extensionRequest) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface extend evaluator requires a surfaceExtend feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try extensionRequest.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        guard case let .closed(lowerU, upperU) = extensionRequest.uDomain,
              case let .closed(lowerV, upperV) = extensionRequest.vDomain else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface extend target domains must be finite."
            )
        }
        let target = try targetResolver.resolve(
            extensionRequest.target,
            featureID: feature.id,
            context: context
        )
        let sourceBodyID = target.bodyID
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: sourceBodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let source = try sourceSheet(
            target: target,
            context: context,
            featureID: feature.id
        )
        let targetBounds = RectangularSurfaceParameterBounds(
            lowerU: lowerU,
            upperU: upperU,
            lowerV: lowerV,
            upperV: upperV
        )
        try boundsValidator.validate(
            targetBounds,
            on: source.surface,
            tolerance: context.tolerance
        )

        let sourceLoops = source.loops.map(\.trimLoop)
        let validatedSource = try loopValidator.validate(
            sourceLoops,
            on: source.surface,
            inside: targetBounds,
            tolerance: context.tolerance
        )
        let targetArea = (upperU - lowerU) * (upperV - lowerV)
        let scale = max(abs(targetArea), 1.0)
        let minimumAddedArea = max(
            context.tolerance.distance * context.tolerance.distance,
            context.tolerance.relative * scale,
            Double.ulpOfOne * scale * 4_096.0
        )
        let certifiedAddedArea = targetArea
            - validatedSource.outerParameterAreaUpperBound
        guard certifiedAddedArea > minimumAddedArea else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                featureID: feature.id,
                residual: certifiedAddedArea,
                tolerance: context.tolerance,
                message: "Surface extend must add a certifiably nonzero region outside the source outer loop."
            )
        }

        let outerPcurves = rectangularBoundary(for: targetBounds)
        let outerLoop = BRepSewingLoop(
            stableID: "surfaceExtend:outer",
            role: .outer,
            edges: try outerPcurves.enumerated().map { index, pcurve in
                try sewingEdge(
                    stableID: "surfaceExtend:outer:edge:\(index)",
                    pcurve: pcurve,
                    surface: source.surface,
                    tolerance: context.tolerance
                )
            }
        )
        let innerLoops = try source.loops
            .filter { $0.trimLoop.role == .inner }
            .enumerated()
            .map { loopIndex, loop in
                BRepSewingLoop(
                    stableID: "surfaceExtend:inner:\(loopIndex)",
                    role: .inner,
                    edges: try loop.edges.enumerated().map { edgeIndex, edge in
                        try sewingEdge(
                            stableID: "surfaceExtend:inner:\(loopIndex):edge:\(edgeIndex)",
                            pcurve: edge.pcurve,
                            surface: source.surface,
                            parentSubshapeIDs: edge.parentSubshapeIDs,
                            startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                            endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
                            tolerance: context.tolerance
                        )
                    }
                )
            }
        let sewn = try sewer.sew(BRepSewingRequest(
            featureID: feature.id,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "surfaceExtend:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "surfaceExtend:face",
                    surface: source.surface,
                    orientation: source.faceOrientation,
                    loops: [outerLoop] + innerLoops,
                    parentSubshapeIDs: source.faceParentSubshapeIDs
                )],
                orientation: source.shellOrientation
            )],
            bodyParentSubshapeIDs: source.bodyParentSubshapeIDs
        ), tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: sourceBodyID,
            with: sewn.bodyID,
            from: sewn.brep,
            in: context.brep
        )
        try model.validate(level: .exact, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func sourceSheet(
        target: ResolvedSurfaceOperationTarget,
        context: EvaluationContext,
        featureID: FeatureID
    ) throws -> SourceSheet {
        guard target.body.shellIDs == [target.shellID],
              target.shell.faceIDs == [target.faceID] else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact surface extend requires the selected face to be the only face of its sheet body."
            )
        }
        let bodyParents = context.subshapeIDs(for: .body(target.bodyID))
        let faceParents = context.subshapeIDs(for: .face(target.faceID))
        guard bodyParents.isEmpty == false, faceParents.isEmpty == false else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                tolerance: context.tolerance,
                "Surface extend requires indexed body and face provenance."
            )
        }
        var sourceLoops: [SourceLoop] = []
        for loopID in target.face.loops {
            guard let loop = context.brep.loops[loopID] else {
                throw kernelError(
                    .missingReference,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    "Surface extend source loop is missing."
                )
            }
            let role: SurfaceTrimLoopRole = loop.role == .outer ? .outer : .inner
            var edges: [SourceBoundaryEdge] = []
            for coedge in loop.coedges {
                guard let edge = context.brep.edges[coedge.edgeID],
                      let pcurve = coedge.surfaceParameterCurve else {
                    throw kernelError(
                        .topologyFailure,
                        featureID: featureID,
                        tolerance: context.tolerance,
                        "Surface extend requires an exact pcurve on every source coedge."
                    )
                }
                let startVertexID: VertexID
                let endVertexID: VertexID
                switch coedge.orientation {
                case .forward:
                    startVertexID = edge.startVertexID
                    endVertexID = edge.endVertexID
                case .reversed:
                    startVertexID = edge.endVertexID
                    endVertexID = edge.startVertexID
                }
                let edgeParents = context.subshapeIDs(for: .edge(edge.id))
                let startParents = context.subshapeIDs(for: .vertex(startVertexID))
                let endParents = context.subshapeIDs(for: .vertex(endVertexID))
                guard edgeParents.isEmpty == false,
                      startParents.isEmpty == false,
                      endParents.isEmpty == false else {
                    throw kernelError(
                        .missingReference,
                        featureID: featureID,
                        tolerance: context.tolerance,
                        "Surface extend requires indexed boundary provenance."
                    )
                }
                edges.append(SourceBoundaryEdge(
                    pcurve: pcurve,
                    parentSubshapeIDs: edgeParents,
                    startVertexParentSubshapeIDs: startParents,
                    endVertexParentSubshapeIDs: endParents
                ))
            }
            sourceLoops.append(SourceLoop(role: role, edges: edges))
        }
        guard sourceLoops.filter({ $0.trimLoop.role == .outer }).count == 1 else {
            throw kernelError(
                .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                "Surface extend requires exactly one outer trim loop."
            )
        }
        return SourceSheet(
            surface: target.surface,
            faceOrientation: target.face.orientation,
            shellOrientation: target.shell.orientation,
            bodyParentSubshapeIDs: bodyParents,
            faceParentSubshapeIDs: faceParents,
            loops: sourceLoops
        )
    }

    private func rectangularBoundary(
        for bounds: RectangularSurfaceParameterBounds
    ) -> [SurfaceParameterCurve] {
        [
            .constantV(
                v: bounds.lowerV,
                uStart: bounds.lowerU,
                uEnd: bounds.upperU
            ),
            .constantU(
                u: bounds.upperU,
                vStart: bounds.lowerV,
                vEnd: bounds.upperV
            ),
            .constantV(
                v: bounds.upperV,
                uStart: bounds.upperU,
                uEnd: bounds.lowerU
            ),
            .constantU(
                u: bounds.lowerU,
                vStart: bounds.upperV,
                vEnd: bounds.lowerV
            ),
        ]
    }

    private func sewingEdge(
        stableID: String,
        pcurve: SurfaceParameterCurve,
        surface: Surface3D,
        parentSubshapeIDs: [SubshapeID] = [],
        startVertexParentSubshapeIDs: [SubshapeID] = [],
        endVertexParentSubshapeIDs: [SubshapeID] = [],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let startParameter = try pcurve.startParameter(tolerance: tolerance)
        let endParameter = try pcurve.endParameter(tolerance: tolerance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .surfaceLift(SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: pcurve
            )),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: try surface.point(
                u: startParameter.u,
                v: startParameter.v,
                tolerance: tolerance
            ),
            endPoint: try surface.point(
                u: endParameter.u,
                v: endParameter.v,
                tolerance: tolerance
            ),
            surfaceParameterCurve: pcurve,
            parentSubshapeIDs: parentSubshapeIDs,
            startVertexParentSubshapeIDs: startVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: endVertexParentSubshapeIDs
        )
    }

    private func kernelError(
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

    private struct SourceSheet {
        let surface: Surface3D
        let faceOrientation: Orientation
        let shellOrientation: Orientation
        let bodyParentSubshapeIDs: [SubshapeID]
        let faceParentSubshapeIDs: [SubshapeID]
        let loops: [SourceLoop]
    }

    private struct SourceLoop {
        let role: SurfaceTrimLoopRole
        let edges: [SourceBoundaryEdge]

        var trimLoop: SurfaceTrimLoop {
            SurfaceTrimLoop(role: role, parameterCurves: edges.map(\.pcurve))
        }
    }

    private struct SourceBoundaryEdge {
        let pcurve: SurfaceParameterCurve
        let parentSubshapeIDs: [SubshapeID]
        let startVertexParentSubshapeIDs: [SubshapeID]
        let endVertexParentSubshapeIDs: [SubshapeID]
    }
}
