import CADCore

public enum FeatureNodeFactory {
    public static func make(
        operation: FeatureOperation,
        id: FeatureID = FeatureID(),
        name: String? = nil,
        in document: CADDocument,
        tolerance: ModelingTolerance = .standard
    ) throws -> FeatureNode {
        switch operation {
        case let .sketch(sketch):
            try sketch.validate(tolerance: tolerance)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                outputs: [FeatureOutput(role: .profile), FeatureOutput(role: .curve)]
            )
        case let .extrude(extrude):
            try validateProfileSource(extrude.profile, in: document)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                inputs: [FeatureInput(featureID: extrude.profile.featureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .revolve(revolve):
            try validateProfileSource(revolve.profile, in: document)
            try revolve.validate(tolerance: tolerance)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                inputs: [FeatureInput(featureID: revolve.profile.featureID, role: .profile)],
                outputs: [FeatureOutput(role: .body)]
            )
        case let .sweep(sweep):
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
        case let .loft(loft):
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
        case let .boolean(boolean):
            try boolean.validate()
            for target in boolean.targets {
                try validateSource(target.featureID, role: .body, in: document)
            }
            try validateSource(boolean.tool.featureID, role: .body, in: document)
            let inputs = boolean.targets.map { FeatureInput(featureID: $0.featureID, role: .target) }
                + [FeatureInput(featureID: boolean.tool.featureID, role: .target)]
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                inputs: inputs,
                outputs: [FeatureOutput(role: .body)]
            )
        case let .polySpline(polySpline):
            try polySpline.validate(tolerance: tolerance)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                outputs: [FeatureOutput(role: .sheet)]
            )
        case let .bSplineSurface(surface):
            try surface.validate(tolerance: tolerance)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                outputs: [FeatureOutput(role: .sheet)]
            )
        case let .faceLoopOffset(feature):
            try feature.validate()
            try validateSource(feature.target.featureID, role: .body, in: document)
            return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
        case let .edgeOffset(feature):
            try feature.validate()
            try validateSource(feature.target.featureID, role: .body, in: document)
            return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
        case let .faceKnife(feature):
            try feature.validate()
            try validateSource(feature.target.featureID, role: .body, in: document)
            return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
        case let .faceDelete(feature):
            try feature.validate()
            try validateSource(feature.target.featureID, role: .body, in: document)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                inputs: [FeatureInput(featureID: feature.target.featureID, role: .target)],
                outputs: [FeatureOutput(role: .sheet)]
            )
        case let .faceDraft(feature):
            try feature.validate()
            try validateSource(feature.target.featureID, role: .body, in: document)
            return bodyNode(id: id, name: name, operation: operation, input: feature.target.featureID, role: .target)
        case let .bridgeCurve(feature):
            try feature.validate(tolerance: tolerance)
            return FeatureNode(
                id: id,
                name: name,
                operation: operation,
                outputs: [FeatureOutput(role: .curve)]
            )
        case let .curveEdit(feature):
            try feature.validate(tolerance: tolerance)
            try validateSource(feature.source.featureID, role: .curve, in: document)
            return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
        case let .curveOffset(feature):
            try feature.validate(tolerance: tolerance)
            try validateSource(feature.source.featureID, role: .curve, in: document)
            return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
        case let .curveTrim(feature):
            try feature.validate(tolerance: tolerance)
            try validateSource(feature.source.featureID, role: .curve, in: document)
            return curveNode(id: id, name: name, operation: operation, input: feature.source.featureID)
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
