import CADCore

public enum FeatureNodeFactory {
    public static func make(
        operation: FeatureOperation,
        id: FeatureID = FeatureID(),
        name: String? = nil,
        in document: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> FeatureNode {
        switch operation {
        case .sketch:
            func run() throws -> FeatureNode {
                guard case let .sketch(sketch) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try sketch.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .profile), FeatureOutput(role: .curve)]
                )
            }
            return try run()
        case .primitive:
            func run() throws -> FeatureNode {
                guard case let .primitive(primitive) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try primitive.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .body)]
                )
            }
            return try run()
        case .extrude:
            func run() throws -> FeatureNode {
                guard case let .extrude(extrude) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try validateProfileSource(extrude.profile, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: extrude.profile.featureID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            }
            return try run()
        case .revolve:
            func run() throws -> FeatureNode {
                guard case let .revolve(revolve) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try validateProfileSource(revolve.profile, in: document)
                try revolve.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: revolve.profile.featureID, role: .profile)],
                    outputs: [FeatureOutput(role: .body)]
                )
            }
            return try run()
        case .sweep:
            func run() throws -> FeatureNode {
                guard case let .sweep(sweep) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try sweep.validate()
                for section in sweep.sections {
                    try validateSource(section.featureID, role: section.inputRole, in: document)
                }
                try validateSource(sweep.path.featureID, role: .curve, in: document)
                for guide in sweep.guides {
                    try validateSource(guide.featureID, role: .curve, in: document)
                }
                for target in sweep.targets {
                    try validateSource(target.featureID, role: .body, in: document)
                }
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: sweepInputs(for: sweep),
                    outputs: [FeatureOutput(role: sweepOutputRole(for: sweep.options.resultKind))]
                )
            }
            return try run()
        case .loft:
            func run() throws -> FeatureNode {
                guard case let .loft(loft) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try loft.validate()
                for section in loft.sections {
                    try validateProfileSource(section.profile, in: document)
                }
                for guide in loft.guides {
                    try validateCurveSource(guide.featureID, owner: "Loft guide", in: document)
                }
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: loftInputs(for: loft),
                    outputs: [FeatureOutput(role: loftOutputRole(for: loft.options.resultKind))]
                )
            }
            return try run()
        case .boolean:
            func run() throws -> FeatureNode {
                guard case let .boolean(boolean) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try boolean.validate()
                for target in boolean.targets {
                    try validateSource(target.featureID, role: .body, in: document)
                }
                try validateSource(boolean.tool.featureID, role: .body, in: document)
                let inputs = boolean.targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
                    + [FeatureInput(featureID: boolean.tool.featureID, role: .body)]
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: inputs,
                    outputs: [FeatureOutput(role: .body)]
                )
            }
            return try run()
        case .polySpline:
            func run() throws -> FeatureNode {
                guard case let .polySpline(polySpline) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try polySpline.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .bSplineSurface:
            func run() throws -> FeatureNode {
                guard case let .bSplineSurface(surface) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try surface.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .patchSurface:
            func run() throws -> FeatureNode {
                guard case let .patchSurface(patch) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try patch.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .bridgeSurface:
            func run() throws -> FeatureNode {
                guard case let .bridgeSurface(bridge) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try bridge.validate(tolerance: tolerance)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .faceLoopOffset:
            func run() throws -> FeatureNode {
                guard case let .faceLoopOffset(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .edgeOffset:
            func run() throws -> FeatureNode {
                guard case let .edgeOffset(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .faceKnife:
            func run() throws -> FeatureNode {
                guard case let .faceKnife(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .faceDelete:
            func run() throws -> FeatureNode {
                guard case let .faceDelete(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: feature.target.featureID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .faceDraft:
            func run() throws -> FeatureNode {
                guard case let .faceDraft(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .faceOffset:
            func run() throws -> FeatureNode {
                guard case let .faceOffset(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .faceMove:
            func run() throws -> FeatureNode {
                guard case let .faceMove(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .edgeMove:
            func run() throws -> FeatureNode {
                guard case let .edgeMove(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .vertexMove:
            func run() throws -> FeatureNode {
                guard case let .vertexMove(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .linearPattern:
            func run() throws -> FeatureNode {
                guard case let .linearPattern(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .radialPattern:
            func run() throws -> FeatureNode {
                guard case let .radialPattern(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .gridPattern:
            func run() throws -> FeatureNode {
                guard case let .gridPattern(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .curveDrivenPattern:
            func run() throws -> FeatureNode {
                guard case let .curveDrivenPattern(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                try validateSource(feature.path.featureID, role: .curve, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [
                        FeatureInput(featureID: feature.target.featureID, role: .target),
                        FeatureInput(featureID: feature.path.featureID, role: .path),
                    ],
                    outputs: [FeatureOutput(role: .body)]
                )
            }
            return try run()
        case .mirror:
            func run() throws -> FeatureNode {
                guard case let .mirror(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .chamfer:
            func run() throws -> FeatureNode {
                guard case let .chamfer(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .fillet:
            func run() throws -> FeatureNode {
                guard case let .fillet(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .g2Blend:
            func run() throws -> FeatureNode {
                guard case let .g2Blend(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .setbackCorner:
            func run() throws -> FeatureNode {
                guard case let .setbackCorner(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .shell:
            func run() throws -> FeatureNode {
                guard case let .shell(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .body, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .thicken:
            func run() throws -> FeatureNode {
                guard case let .thicken(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .sheet, in: document)
                return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
            }
            return try run()
        case .bridgeCurve:
            func run() throws -> FeatureNode {
                guard case let .bridgeCurve(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.start.curve.featureID, role: .curve, in: document)
                try validateSource(feature.end.curve.featureID, role: .curve, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [
                        FeatureInput(featureID: feature.start.curve.featureID, role: .curve),
                        FeatureInput(featureID: feature.end.curve.featureID, role: .target),
                    ],
                    outputs: [FeatureOutput(role: .curve)]
                )
            }
            return try run()
        case .curveEdit:
            func run() throws -> FeatureNode {
                guard case let .curveEdit(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.source.featureID, role: .curve, in: document)
                return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
            }
            return try run()
        case .curveOffset:
            func run() throws -> FeatureNode {
                guard case let .curveOffset(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.source.featureID, role: .curve, in: document)
                return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
            }
            return try run()
        case .projectCurve:
            func run() throws -> FeatureNode {
                guard case let .projectCurve(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.source.featureID, role: .curve, in: document)
                return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
            }
            return try run()
        case .curveTrim:
            func run() throws -> FeatureNode {
                guard case let .curveTrim(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.source.featureID, role: .curve, in: document)
                return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
            }
            return try run()
        case .curveExtend:
            func run() throws -> FeatureNode {
                guard case let .curveExtend(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.source.featureID, role: .curve, in: document)
                return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
            }
            return try run()
        case .curveMatch:
            func run() throws -> FeatureNode {
                guard case let .curveMatch(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.source.featureID, role: .curve, in: document)
                try validateSource(feature.target.featureID, role: .curve, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [
                        FeatureInput(featureID: feature.source.featureID, role: .curve),
                        FeatureInput(featureID: feature.target.featureID, role: .target),
                    ],
                    outputs: [FeatureOutput(role: .curve)]
                )
            }
            return try run()
        case .surfaceOffset:
            func run() throws -> FeatureNode {
                guard case let .surfaceOffset(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.target.featureID, role: .sheet, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: feature.target.featureID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .surfaceTrim:
            func run() throws -> FeatureNode {
                guard case let .surfaceTrim(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .sheet, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: feature.target.featureID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .surfaceExtend:
            func run() throws -> FeatureNode {
                guard case let .surfaceExtend(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate(tolerance: tolerance)
                try validateSource(feature.target.featureID, role: .sheet, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [FeatureInput(featureID: feature.target.featureID, role: .target)],
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        case .surfaceMatch:
            func run() throws -> FeatureNode {
                guard case let .surfaceMatch(feature) = operation else {
                    throw FeatureEvaluationError.invalidGraph("Feature node factory dispatch expected a different operation payload.")
                }
                try feature.validate()
                try validateSource(feature.source.featureID, role: .sheet, in: document)
                try validateSource(feature.target.featureID, role: .sheet, in: document)
                return FeatureNode(
                    id: id,
                    name: name,
                    operation: operation,
                    inputs: [
                        FeatureInput(featureID: feature.source.featureID, role: .sheet),
                        FeatureInput(featureID: feature.target.featureID, role: .target),
                    ],
                    outputs: [FeatureOutput(role: .sheet)]
                )
            }
            return try run()
        }
    }

    private static func bodyNode(
        id: FeatureID,
        name: String?,
        operation: FeatureOperation,
        input: FeatureID,
        role: FeaturePort
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            name: name,
            operation: operation,
            inputs: [FeatureInput(featureID: input, role: role)],
            outputs: [FeatureOutput(role: .body)]
        )
    }

    private static func curveNode(
        id: FeatureID,
        name: String?,
        operation: FeatureOperation,
        input: FeatureID
    ) -> FeatureNode {
        FeatureNode(
            id: id,
            name: name,
            operation: operation,
            inputs: [FeatureInput(featureID: input, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
    }

    private static func validateProfileSource(
        _ profile: ProfileReference,
        in document: CADDocument
    ) throws {
        try profile.validate()
        try validateSource(profile.featureID, role: .profile, in: document)
    }

    private static func validateCurveSource(
        _ featureID: FeatureID,
        owner: String,
        in document: CADDocument
    ) throws {
        do {
            try validateSource(featureID, role: .curve, in: document)
        } catch let error as FeatureEvaluationError {
            if case .invalidGraph = error {
                throw FeatureEvaluationError.invalidGraph("\(owner) source must declare a curve output.")
            }
            throw error
        }
    }

    private static func validateSource(
        _ featureID: FeatureID,
        role: FeaturePort,
        in document: CADDocument
    ) throws {
        guard let source = document.designGraph.nodes[featureID] else {
            throw FeatureEvaluationError.missingInput("Feature source \(featureID) was not found.")
        }
        guard source.outputs.contains(where: { $0.role == role }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Feature source \(featureID) does not declare the required \(role.rawValue) output."
            )
        }
    }

    private static func sweepInputs(for sweep: SweepFeature) -> [FeatureInput] {
        sweep.sections.map { FeatureInput(featureID: $0.featureID, role: $0.inputRole) }
            + [FeatureInput(featureID: sweep.path.featureID, role: .path)]
            + sweep.guides.map { FeatureInput(featureID: $0.featureID, role: .guide) }
            + sweep.targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
    }

    private static func loftInputs(for loft: LoftFeature) -> [FeatureInput] {
        loft.sections.map { FeatureInput(featureID: $0.featureID, role: .profile) }
            + loft.guides.map { FeatureInput(featureID: $0.featureID, role: .guide) }
    }

    private static func sweepOutputRole(for resultKind: SweepResultKind) -> FeaturePort {
        resultKind == .solid ? .body : .sheet
    }

    private static func loftOutputRole(for resultKind: LoftResultKind) -> FeaturePort {
        resultKind == .solid ? .body : .sheet
    }
}
