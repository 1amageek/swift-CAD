import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BooleanFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let applicator: any BooleanOperationApplying
    private let toolRelocator: (any ExactBodyPatternRebuilding)?

    /// An evaluator for Booleans whose operands are all combined where they were evaluated.
    public init(applicator: any BooleanOperationApplying) {
        self.applicator = applicator
        self.toolRelocator = nil
    }

    /// An evaluator that also moves placed operands into the result's frame with `toolRelocator`.
    package init(
        applicator: any BooleanOperationApplying,
        toolRelocator: any ExactBodyPatternRebuilding
    ) {
        self.applicator = applicator
        self.toolRelocator = toolRelocator
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .boolean(boolean) = feature.operation else {
            throw FeatureEvaluationError.invalidGraph(
                "BooleanFeatureEvaluator received a non-boolean feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try boolean.validate()
        }
        let targetBodyIDs = try boolean.targets.map { try context.bodyID(generatedBy: $0.featureID) }
        let toolBodyIDs = try boolean.tools.map { try context.bodyID(generatedBy: $0.featureID) }
        return try evaluateStaged(
            boolean, targetBodyIDs: targetBodyIDs, toolBodyIDs: toolBodyIDs, featureID: feature.id, context: context
        )
    }

    /// Moves every placed operand rigidly into the result's frame, unites several tools into one,
    /// combines, and publishes the result as if the inputs had been combined directly. The result
    /// replaces the targets; Keep Tools puts every tool back, unchanged, where it was evaluated.
    private func evaluateStaged(
        _ boolean: BooleanFeature,
        targetBodyIDs: [BodyID],
        toolBodyIDs: [BodyID],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var stages = FeatureEvaluationStages(context)
        func relocated(_ bodyID: BodyID, placement: RigidTransform3D?, ordinal: Int) throws -> BodyID {
            guard let placement else { return bodyID }
            guard let toolRelocator else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "This evaluator cannot move a placed Boolean operand."
                )
            }
            try placement.validate(tolerance: context.tolerance)
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanOperandPlacement, ordinal: UInt64(ordinal))
            let staged = stages.context
            let moved = try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: context.tolerance) {
                try toolRelocator.relocate(
                    featureID: stageID,
                    sourceBodyID: bodyID,
                    transform: placement,
                    stablePrefix: "boolean:placedOperand",
                    context: staged
                )
            }
            stages.apply(moved)
            return try stages.publishedBody(of: moved, featureID: featureID, what: "Moving a Boolean operand")
        }
        let targets = try zip(targetBodyIDs, boolean.targets).enumerated().map { ordinal, pair in
            try relocated(pair.0, placement: pair.1.placement, ordinal: ordinal)
        }
        var tools = try zip(toolBodyIDs, boolean.tools).enumerated().map { ordinal, pair in
            try relocated(pair.0, placement: pair.1.placement, ordinal: targetBodyIDs.count + ordinal)
        }
        // A Region Boolean divides space by every operand's faces alike: nothing is united.
        if boolean.operation == .region {
            let final = try combine(
                .region, targets: targets + tools.dropLast(), tool: tools[tools.count - 1],
                materials: .default, featureID: featureID, context: stages.context
            )
            let published = try stages.publish(final, featureID: featureID)
            guard boolean.keepTools else { return published }
            return try stages.restoringInputBodies(toolBodyIDs, into: published)
        }
        // The tools act as one region: unite them, one after another. Their union is a volume,
        // so several tools are solids taken as their volumes.
        if tools.count > 1 {
            guard boolean.toolMaterial == .default || boolean.toolMaterial == .inside,
                  tools.allSatisfy({ stages.context.brep.bodies[$0]?.kind == .solid }) else {
                throw KernelError(
                    phase: .evaluation,
                    code: .invalidInput,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "Several Boolean tools act as their union, so they must be solids taken as their volumes."
                )
            }
        }
        var unionOrdinal: UInt64 = 0
        while tools.count > 1 {
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanToolUnion, ordinal: unionOrdinal)
            unionOrdinal += 1
            let united = try combine(.union, targets: [tools[0]], tool: tools[1], materials: .default, featureID: stageID, context: stages.context)
            stages.apply(united)
            tools = [try stages.publishedBody(of: united, featureID: featureID, what: "Uniting the Boolean tools")] + tools.dropFirst(2)
        }
        // Plasticity's Slice keeps the tool's pieces outside the targets too: the tool less every
        // target, made first, then the operands restored for the targets' slice.
        let materials = BooleanMaterials(target: boolean.targetMaterial, tool: boolean.toolMaterial)
        var remainder: [SubshapeID: TopologyReference] = [:]
        // FIXME(INCOMPLETE_IMPLEMENTATION): a Slice with a sheet operand or operand materials other
        // than Default keeps only the targets' pieces; the tool's pieces are not made, because
        // Plasticity's pieces for those materials are not determined (its page's Target Outside /
        // Tool Empty note names three results where its figure shows four). Production path:
        // BooleanFeatureEvaluator from Boolean Slice. Complete only when the tool's pieces for
        // every material pair are specified and verified by volume per piece.
        if boolean.operation == .slice, materials == .default,
           (targets + tools).allSatisfy({ stages.context.brep.bodies[$0]?.kind == .solid }) {
            let operands = targets + tools
            let beforeRemainder = stages.context
            var piece = tools[0]
            var applied = false
            for (ordinal, target) in targets.enumerated() {
                let stageID = featureEvaluationStageID(featureID: featureID, domain: .sliceToolRemainder, ordinal: UInt64(ordinal))
                let cut: EvaluationResult
                do {
                    cut = try combine(.difference, targets: [piece], tool: target, materials: .default, featureID: stageID, context: stages.context)
                } catch let error as KernelError where error.code == .emptyResult {
                    // The targets hold all of the tool: it leaves no piece of its own, and a piece
                    // an earlier target left goes.
                    if applied {
                        let model = stages.context.brep
                        stages.apply(EvaluationResult(
                            brep: try BRepBodySubmodelExtractor().extract(bodyIDs: Set(model.bodies.keys).subtracting([piece]), from: model),
                            removedSubshapeIDs: Set(remainder.keys)
                        ))
                    }
                    remainder = [:]
                    break
                }
                stages.apply(cut)
                applied = true
                remainder = cut.subshapes
                piece = try stages.publishedBody(of: cut, featureID: featureID, what: "The tool less a Slice target")
            }
            if applied { try stages.restoreBodies(operands, from: beforeRemainder) }
        }
        var final = try combine(
            boolean.operation, targets: targets, tool: tools[0],
            materials: materials, featureID: featureID, context: stages.context
        )
        // The tool's pieces join the Slice's body as components of their own, so one body shows
        // every piece, and publish under the Slice's identity, tracing to their stage names.
        let pieceBodies = Set(remainder.values.compactMap { reference -> BodyID? in
            if case let .body(id) = reference { return id }
            return nil
        })
        if let pieceBody = pieceBodies.first, pieceBodies.count == 1,
           let resultBody = final.subshapes.values.compactMap({ reference -> BodyID? in
               if case let .body(id) = reference, id != pieceBody { return id }
               return nil
           }).first,
           case let .solid(pieceComponents)? = final.brep.bodies[pieceBody]?.topology,
           var body = final.brep.bodies[resultBody], case let .solid(components) = body.topology {
            body.topology = .solid(components: components + pieceComponents)
            final.brep.bodies[resultBody] = body
            final.brep.bodies.removeValue(forKey: pieceBody)
            remainder = remainder.filter { $0.value != .body(pieceBody) }
        } else if remainder.isEmpty == false {
            throw KernelError(phase: .topology, code: .topologyFailure, featureID: featureID, tolerance: context.tolerance,
                              message: "A Slice's tool pieces and target pieces must each make one solid body.")
        }
        func exists(_ reference: TopologyReference) -> Bool {
            switch reference {
            case let .body(id): final.brep.bodies[id] != nil
            case let .face(id): final.brep.faces[id] != nil
            case let .edge(id): final.brep.edges[id] != nil
            case let .vertex(id): final.brep.vertices[id] != nil
            }
        }
        for (subshapeID, reference) in remainder.sorted(by: { $0.key < $1.key }) where exists(reference) {
            let published = SubshapeID(featureID: featureID, role: "sliceToolPiece.\(subshapeID.role)", ordinal: subshapeID.ordinal)
            final.subshapes[published] = reference
            final.lineage[published] = TopologyLineage(output: published, parents: [subshapeID], relation: .preserved)
        }
        final.validatedBRep = nil
        let published = try stages.publish(final, featureID: featureID)
        guard boolean.keepTools else { return published }
        return try stages.restoringInputBodies(toolBodyIDs, into: published)
    }

    /// One pass of the Boolean pipeline in `context`, consuming its operands.
    private func combine(
        _ operation: BooleanOperation,
        targets: [BodyID],
        tool: BodyID,
        materials: BooleanMaterials,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let toolSubshapes = context.subshapes.entries.filter { _, reference in
            context.brep.contains(reference, inBody: tool)
        }
        return try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: context.tolerance) {
            try applicator.apply(
                operation: operation,
                targetBodyIDs: targets,
                toolBodyID: tool,
                keepTools: false,
                featureID: featureID,
                model: context.brep,
                subshapes: context.subshapes.entries,
                toolSubshapes: toolSubshapes,
                inputLineage: context.lineage,
                materials: materials,
                tolerance: context.tolerance
            )
        }
    }
}
