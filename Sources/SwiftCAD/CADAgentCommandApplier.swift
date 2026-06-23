import CADCore
import CADIR

public struct CADAgentCommandApplier: Sendable {
    public init() {}

    public func apply(
        _ command: CADAgentCommand,
        to document: CADDocument,
        tolerance: ModelingTolerance = .standard
    ) throws -> CADAgentCommandResult {
        try document.validate(tolerance: tolerance)
        var updatedDocument = document
        if case let .addSelectionDimension(command) = command {
            let dimension = command.selectionDimension()
            try dimension.validate(parameters: updatedDocument.parameters, tolerance: tolerance)
            guard updatedDocument.selectionDimensions.contains(where: { $0.id == dimension.id }) == false else {
                throw FeatureEvaluationError.invalidGraph("Agent command selection dimension ID already exists.")
            }
            updatedDocument.selectionDimensions.append(dimension)
            try updatedDocument.validate(tolerance: tolerance)
            return CADAgentCommandResult(document: updatedDocument, addedSelectionDimensionID: dimension.id)
        }
        let featureNode = try node(for: command, in: updatedDocument, tolerance: tolerance)
        guard updatedDocument.designGraph.nodes[featureNode.id] == nil else {
            throw FeatureEvaluationError.invalidGraph("Agent command feature ID already exists.")
        }
        updatedDocument.designGraph.nodes[featureNode.id] = featureNode
        updatedDocument.designGraph.order.append(featureNode.id)
        updatedDocument.designGraph.dependencies.append(contentsOf: dependencies(for: featureNode))
        updatedDocument.designGraph.revision = updatedDocument.designGraph.revision.advanced()
        try updatedDocument.validate(tolerance: tolerance)
        return CADAgentCommandResult(document: updatedDocument, addedFeatureID: featureNode.id)
    }

    private func node(
        for command: CADAgentCommand,
        in document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> FeatureNode {
        switch command {
        case let .addSketch(command):
            try command.sketch.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .sketch(command.sketch),
                outputs: [
                    FeatureOutput(role: .profile),
                    FeatureOutput(role: .curve),
                ]
            )
        case let .addExtrude(command):
            try validateProfileSource(command.extrude.profile, in: document)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .extrude(command.extrude),
                inputs: [FeatureInput(featureID: command.extrude.profile.featureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addSweep(command):
            try command.sweep.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .sweep(command.sweep),
                inputs: sweepInputs(for: command.sweep),
                outputs: [FeatureOutput(role: sweepOutputRole(for: command.sweep.options.resultKind))]
            )
        case let .addPolySpline(command):
            try command.polySpline.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .polySpline(command.polySpline),
                outputs: [FeatureOutput(role: .sheet)]
            )
        case let .addFaceLoopOffset(command):
            try command.faceLoopOffset.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .faceLoopOffset(command.faceLoopOffset),
                inputs: [FeatureInput(featureID: command.faceLoopOffset.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addEdgeOffset(command):
            try command.edgeOffset.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .edgeOffset(command.edgeOffset),
                inputs: [FeatureInput(featureID: command.edgeOffset.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addFaceKnife(command):
            try command.faceKnife.validate()
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .faceKnife(command.faceKnife),
                inputs: [FeatureInput(featureID: command.faceKnife.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .addBridgeCurve(command):
            try command.bridgeCurve.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .bridgeCurve(command.bridgeCurve),
                outputs: [FeatureOutput(role: .curve)]
            )
        case let .addCurveEdit(command):
            try command.curveEdit.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .curveEdit(command.curveEdit),
                inputs: [FeatureInput(featureID: command.curveEdit.source.featureID, role: .curve)],
                outputs: [FeatureOutput(role: .curve)]
            )
        case let .addCurveOffset(command):
            try command.curveOffset.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .curveOffset(command.curveOffset),
                inputs: [FeatureInput(featureID: command.curveOffset.source.featureID, role: .curve)],
                outputs: [FeatureOutput(role: .curve)]
            )
        case let .addCurveTrim(command):
            try command.curveTrim.validate(tolerance: tolerance)
            return FeatureNode(
                id: command.featureID ?? FeatureID(),
                name: command.name,
                operation: .curveTrim(command.curveTrim),
                inputs: [FeatureInput(featureID: command.curveTrim.source.featureID, role: .curve)],
                outputs: [FeatureOutput(role: .curve)]
            )
        case .addSelectionDimension:
            throw FeatureEvaluationError.unsupportedOperation(
                "Selection dimension commands are applied outside the feature graph."
            )
        }
    }

    private func validateProfileSource(_ profile: ProfileReference, in document: CADDocument) throws {
        try profile.validate()
        guard let source = document.designGraph.nodes[profile.featureID],
              source.outputs.contains(where: { $0.role == .profile }) else {
            throw FeatureEvaluationError.invalidGraph("Agent extrude command profile source must declare a profile output.")
        }
    }

    private func sweepInputs(for sweep: SweepFeature) -> [FeatureInput] {
        sweep.profiles.map { profile in
            FeatureInput(featureID: profile.featureID, role: .profile)
        } + [
            FeatureInput(featureID: sweep.path.featureID, role: .path),
        ] + sweep.guides.map { guide in
            FeatureInput(featureID: guide.featureID, role: .guide)
        } + sweep.targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        }
    }

    private func dependencies(for node: FeatureNode) -> [DependencyEdge] {
        node.inputs.map { input in
            DependencyEdge(source: input.featureID, target: node.id)
        }
    }

    private func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
        switch resultKind {
        case .solid:
            return .body
        case .sheet:
            return .sheet
        }
    }
}
