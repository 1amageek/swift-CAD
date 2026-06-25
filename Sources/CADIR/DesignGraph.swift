import CADCore

public struct DesignGraph: Codable, Sendable {
    public var nodes: [FeatureID: FeatureNode]
    public var order: [FeatureID]
    public var dependencies: [DependencyEdge]
    public var revision: DocumentRevision

    public init(
        nodes: [FeatureID: FeatureNode] = [:],
        order: [FeatureID] = [],
        dependencies: [DependencyEdge] = [],
        revision: DocumentRevision = DocumentRevision()
    ) {
        self.nodes = nodes
        self.order = order
        self.dependencies = dependencies
        self.revision = revision
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try revision.validate()
        let orderSet = Set(order)
        guard orderSet.count == order.count else {
            throw FeatureEvaluationError.invalidGraph("Feature order contains duplicate IDs.")
        }
        guard Set(dependencies).count == dependencies.count else {
            throw FeatureEvaluationError.invalidGraph("Dependency edges contain duplicates.")
        }
        let nodeIDs = Set(nodes.keys)
        guard orderSet == nodeIDs else {
            throw FeatureEvaluationError.invalidGraph("Feature order must contain every node exactly once.")
        }
        for (featureID, node) in nodes {
            guard node.id == featureID else {
                throw FeatureEvaluationError.invalidGraph("Feature node key does not match its ID.")
            }
            try validateOperationContract(for: node, tolerance: tolerance)
            for input in node.inputs {
                guard nodes[input.featureID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references a missing node.")
                }
            }
        }
        for dependency in dependencies {
            guard nodes[dependency.source] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency source is missing.")
            }
            guard nodes[dependency.target] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
        }
        try validateAcyclicDependencies()
        try validateOrderRespectsDependencies()
        try validateInputsAreRepresentedByDependencies()
        try validateDependenciesAreRepresentedByInputs()
        try validateActiveFeaturesDoNotDependOnSuppressedSources()
    }

    public func validateExpressions(using parameters: ParameterTable) throws {
        for featureID in order {
            guard let node = nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            switch node.operation {
            case let .sketch(sketch):
                try sketch.validateExpressions(using: parameters)
            case let .extrude(extrude):
                let distance = try parameters.resolvedValue(for: extrude.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "extrude.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .revolve(revolve):
                let angle = try parameters.resolvedValue(for: revolve.angle)
                guard angle.kind == .angle else {
                    throw UnitError.expectedQuantity(
                        operation: "revolve.angle",
                        expected: .angle,
                        actual: angle.kind
                    )
                }
                guard angle.value.isFinite, abs(angle.value) > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(angle.value)
                }
            case let .sweep(sweep):
                let twistAngle = try parameters.resolvedValue(for: sweep.options.twistAngle)
                guard twistAngle.kind == .angle else {
                    throw UnitError.expectedQuantity(
                        operation: "sweep.options.twistAngle",
                        expected: .angle,
                        actual: twistAngle.kind
                    )
                }
                let endScale = try parameters.resolvedValue(for: sweep.options.endScale)
                guard endScale.kind == .scalar else {
                    throw UnitError.expectedQuantity(
                        operation: "sweep.options.endScale",
                        expected: .scalar,
                        actual: endScale.kind
                    )
                }
                guard endScale.value > 0.0 else {
                    throw FeatureEvaluationError.invalidGraph("Sweep end scale must be greater than zero.")
                }
                let distanceFraction = try parameters.resolvedValue(for: sweep.options.distanceFraction)
                guard distanceFraction.kind == .scalar else {
                    throw UnitError.expectedQuantity(
                        operation: "sweep.options.distanceFraction",
                        expected: .scalar,
                        actual: distanceFraction.kind
                    )
                }
                guard distanceFraction.value > 0.0,
                      distanceFraction.value <= 1.0 else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Sweep distance fraction must be greater than 0 and less than or equal to 1."
                    )
                }
            case let .polySpline(polySpline):
                try polySpline.validate(tolerance: .standard)
            case let .faceLoopOffset(faceLoopOffset):
                let distance = try parameters.resolvedValue(for: faceLoopOffset.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "faceLoopOffset.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .edgeOffset(edgeOffset):
                let distance = try parameters.resolvedValue(for: edgeOffset.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "edgeOffset.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .faceKnife(faceKnife):
                try faceKnife.validate()
            case let .bridgeCurve(bridgeCurve):
                try bridgeCurve.validate(tolerance: .standard)
            case let .curveEdit(curveEdit):
                try curveEdit.validate(tolerance: .standard)
            case let .curveOffset(curveOffset):
                let distance = try parameters.resolvedValue(for: curveOffset.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "curveOffset.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .curveTrim(curveTrim):
                try curveTrim.validate(tolerance: .standard)
            }
        }
    }

    private func validateOperationContract(for node: FeatureNode, tolerance: ModelingTolerance) throws {
        guard Set(node.inputs).count == node.inputs.count else {
            throw FeatureEvaluationError.invalidGraph("Feature inputs contain duplicate references.")
        }
        let outputRoles = node.outputs.map(\.role)
        guard Set(outputRoles).count == outputRoles.count else {
            throw FeatureEvaluationError.invalidGraph("Feature outputs contain duplicate roles.")
        }
        for output in node.outputs {
            try output.persistentName?.validate()
        }

        switch node.operation {
        case let .sketch(sketch):
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Sketch features must not declare inputs.")
            }
            let allowedSketchOutputs: Set<FeaturePort> = [.profile, .curve]
            guard outputRoles.isEmpty == false,
                  Set(outputRoles).isSubset(of: allowedSketchOutputs) else {
                throw FeatureEvaluationError.invalidGraph("Sketch features must declare profile or curve outputs.")
            }
            try sketch.validate(tolerance: tolerance)
        case let .extrude(extrude):
            try extrude.profile.validate()
            try extrude.distance.validateLiteralQuantities()
            guard node.inputs == [FeatureInput(featureID: extrude.profile.featureID, role: .profile)] else {
                throw FeatureEvaluationError.invalidGraph("Extrude features must consume the referenced profile input.")
            }
            guard let source = nodes[extrude.profile.featureID],
                  source.outputs.contains(where: { $0.role == .profile }) else {
                throw FeatureEvaluationError.invalidGraph("Extrude profile source must declare a profile output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Extrude features must declare one body output.")
            }
            if case let .vector(vector) = extrude.direction {
                try vector.validate()
            }
        case let .revolve(revolve):
            try revolve.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: revolve.profile.featureID, role: .profile)] else {
                throw FeatureEvaluationError.invalidGraph("Revolve features must consume the referenced profile input.")
            }
            guard let source = nodes[revolve.profile.featureID],
                  source.outputs.contains(where: { $0.role == .profile }) else {
                throw FeatureEvaluationError.invalidGraph("Revolve profile source must declare a profile output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Revolve features must declare one body output.")
            }
        case let .sweep(sweep):
            try sweep.validate()
            let expectedInputs = sweep.sections.map { section in
                FeatureInput(featureID: section.featureID, role: section.inputRole)
            } + [
                FeatureInput(featureID: sweep.path.featureID, role: .path)
            ] + sweep.guides.map { guide in
                FeatureInput(featureID: guide.featureID, role: .guide)
            } + sweep.targets.map { target in
                FeatureInput(featureID: target.featureID, role: .target)
            }
            guard Set(node.inputs) == Set(expectedInputs),
                  node.inputs.count == expectedInputs.count else {
                throw FeatureEvaluationError.invalidGraph("Sweep features must consume the declared section, path, guide, and target inputs.")
            }
            for section in sweep.sections {
                guard let source = nodes[section.featureID],
                      source.outputs.contains(where: { $0.role == section.inputRole }) else {
                    throw FeatureEvaluationError.invalidGraph("Sweep section source must declare a \(section.inputRole.rawValue) output.")
                }
            }
            guard let pathSource = nodes[sweep.path.featureID],
                  pathSource.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Sweep path source must declare a curve output.")
            }
            for guide in sweep.guides {
                guard let guideSource = nodes[guide.featureID],
                      guideSource.outputs.contains(where: { $0.role == .curve }) else {
                    throw FeatureEvaluationError.invalidGraph("Sweep guide source must declare a curve output.")
                }
            }
            for target in sweep.targets {
                guard let targetSource = nodes[target.featureID],
                      targetSource.outputs.contains(where: { $0.role == .body }) else {
                    throw FeatureEvaluationError.invalidGraph("Sweep target source must declare a body output.")
                }
            }
            switch sweep.options.resultKind {
            case .solid:
                guard outputRoles == [.body] else {
                    throw FeatureEvaluationError.invalidGraph("Solid sweep features must declare one body output.")
                }
            case .sheet:
                guard outputRoles == [.sheet] else {
                    throw FeatureEvaluationError.invalidGraph("Sheet sweep features must declare one sheet output.")
                }
            }
        case let .polySpline(polySpline):
            try polySpline.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("PolySpline features must not declare inputs in the inline mesh subset.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("PolySpline features must declare one sheet output.")
            }
        case let .faceLoopOffset(faceLoopOffset):
            try faceLoopOffset.validate()
            guard node.inputs == [FeatureInput(featureID: faceLoopOffset.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face loop offset features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[faceLoopOffset.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face loop offset target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Face loop offset features must declare one body output.")
            }
        case let .edgeOffset(edgeOffset):
            try edgeOffset.validate()
            guard node.inputs == [FeatureInput(featureID: edgeOffset.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Edge offset features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[edgeOffset.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Edge offset target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Edge offset features must declare one body output.")
            }
        case let .faceKnife(faceKnife):
            try faceKnife.validate()
            guard node.inputs == [FeatureInput(featureID: faceKnife.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face Knife features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[faceKnife.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face Knife target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Face Knife features must declare one body output.")
            }
        case let .bridgeCurve(bridgeCurve):
            try bridgeCurve.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Bridge curve features currently use inline endpoint constraints and must not declare inputs.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Bridge curve features must declare one curve output.")
            }
        case let .curveEdit(curveEdit):
            try curveEdit.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: curveEdit.source.featureID, role: .curve)] else {
                throw FeatureEvaluationError.invalidGraph("Curve edit features must consume the referenced curve input.")
            }
            guard let source = nodes[curveEdit.source.featureID],
                  source.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve edit source must declare a curve output.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Curve edit features must declare one curve output.")
            }
        case let .curveOffset(curveOffset):
            try curveOffset.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: curveOffset.source.featureID, role: .curve)] else {
                throw FeatureEvaluationError.invalidGraph("Curve offset features must consume the referenced curve input.")
            }
            guard let source = nodes[curveOffset.source.featureID],
                  source.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve offset source must declare a curve output.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Curve offset features must declare one curve output.")
            }
        case let .curveTrim(curveTrim):
            try curveTrim.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: curveTrim.source.featureID, role: .curve)] else {
                throw FeatureEvaluationError.invalidGraph("Curve trim features must consume the referenced curve input.")
            }
            guard let source = nodes[curveTrim.source.featureID],
                  source.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve trim source must declare a curve output.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Curve trim features must declare one curve output.")
            }
        }
    }

    private func validateAcyclicDependencies() throws {
        var adjacency: [FeatureID: [FeatureID]] = [:]
        for dependency in dependencies {
            adjacency[dependency.source, default: []].append(dependency.target)
        }
        var states: [FeatureID: VisitState] = [:]
        var stack: [FeatureID] = []
        for featureID in nodes.keys.sorted(by: { $0.description < $1.description }) {
            try visit(featureID, adjacency: adjacency, states: &states, stack: &stack)
        }
    }

    private func visit(
        _ featureID: FeatureID,
        adjacency: [FeatureID: [FeatureID]],
        states: inout [FeatureID: VisitState],
        stack: inout [FeatureID]
    ) throws {
        if states[featureID] == .visited {
            return
        }
        if states[featureID] == .visiting {
            let cycleStart = stack.firstIndex(of: featureID) ?? stack.startIndex
            let cycle = (Array(stack[cycleStart...]) + [featureID])
                .map(\.description)
                .joined(separator: " -> ")
            throw FeatureEvaluationError.invalidGraph("Dependency cycle detected: \(cycle).")
        }

        states[featureID] = .visiting
        stack.append(featureID)
        for targetID in adjacency[featureID, default: []].sorted(by: { $0.description < $1.description }) {
            try visit(targetID, adjacency: adjacency, states: &states, stack: &stack)
        }
        stack.removeLast()
        states[featureID] = .visited
    }

    private func validateOrderRespectsDependencies() throws {
        var positions: [FeatureID: Int] = [:]
        positions.reserveCapacity(order.count)
        for (index, featureID) in order.enumerated() {
            positions[featureID] = index
        }
        for dependency in dependencies {
            guard let sourceIndex = positions[dependency.source],
                  let targetIndex = positions[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency references an unordered feature.")
            }
            guard sourceIndex < targetIndex else {
                throw FeatureEvaluationError.invalidGraph("Feature order violates dependency direction.")
            }
        }
        for (featureID, node) in nodes {
            guard let targetIndex = positions[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature node is unordered.")
            }
            for input in node.inputs {
                guard let sourceIndex = positions[input.featureID] else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references an unordered feature.")
                }
                guard sourceIndex < targetIndex else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must appear before the consuming feature.")
                }
            }
        }
    }

    private func validateInputsAreRepresentedByDependencies() throws {
        let dependencySet = Set(dependencies)
        for (featureID, node) in nodes {
            for input in node.inputs {
                let requiredDependency = DependencyEdge(source: input.featureID, target: featureID)
                guard dependencySet.contains(requiredDependency) else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must be represented by a dependency edge.")
                }
            }
        }
    }

    private func validateDependenciesAreRepresentedByInputs() throws {
        for dependency in dependencies {
            guard let target = nodes[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
            guard target.inputs.contains(where: { $0.featureID == dependency.source }) else {
                throw FeatureEvaluationError.invalidGraph("Dependency edge must be represented by a feature input.")
            }
        }
    }

    private func validateActiveFeaturesDoNotDependOnSuppressedSources() throws {
        var suppressedFeatureIDs = Set<FeatureID>()
        for (featureID, node) in nodes where node.isSuppressed {
            suppressedFeatureIDs.insert(featureID)
        }
        guard suppressedFeatureIDs.isEmpty == false else {
            return
        }

        for (_, node) in nodes where !node.isSuppressed {
            for input in node.inputs {
                guard suppressedFeatureIDs.contains(input.featureID) == false else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Active feature input references a suppressed feature."
                    )
                }
            }
        }
        for dependency in dependencies {
            guard nodes[dependency.target]?.isSuppressed != true,
                  suppressedFeatureIDs.contains(dependency.source) else {
                continue
            }
            throw FeatureEvaluationError.invalidGraph(
                "Active feature dependency references a suppressed feature."
            )
        }
    }
}

private enum VisitState {
    case visiting
    case visited
}

public struct DependencyEdge: Codable, Sendable, Hashable {
    public var source: FeatureID
    public var target: FeatureID

    public init(source: FeatureID, target: FeatureID) {
        self.source = source
        self.target = target
    }
}
