import CADCore
import CADTopology

public struct DesignGraph: Codable, Sendable {
    public var nodes: PersistentMap<FeatureID, FeatureNode>
    public var order: [FeatureID]
    public var dependencies: [DependencyEdge]
    public var revision: DocumentRevision

    private enum CodingKeys: String, CodingKey {
        case nodes
        case order
        case dependencies
        case revision
    }

    public init(
        nodes: [FeatureID: FeatureNode] = [:],
        order: [FeatureID] = [],
        dependencies: [DependencyEdge] = [],
        revision: DocumentRevision = DocumentRevision()
    ) {
        self.nodes = PersistentMap(nodes)
        self.order = order
        self.dependencies = dependencies
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.nodes, .order, .dependencies, .revision], in: decoder)
        nodes = PersistentMap(
            try container.decode([FeatureID: FeatureNode].self, forKey: .nodes)
        )
        order = try container.decode([FeatureID].self, forKey: .order)
        dependencies = try container.decode([DependencyEdge].self, forKey: .dependencies)
        revision = try container.decode(DocumentRevision.self, forKey: .revision)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.materializedDictionary(), forKey: .nodes)
        try container.encode(order, forKey: .order)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(revision, forKey: .revision)
    }

    public func validate(tolerance: ModelingTolerance) throws {
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

    public func validateExpressions(
        using parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        for featureID in order {
            guard let node = nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            try validateExpressions(for: node, using: parameters, tolerance: tolerance)
        }
    }

    func validateExpressions(
        for node: FeatureNode,
        using parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws {
        switch node.operation {
            case let .sketch(sketch):
                try sketch.validateExpressions(using: parameters)
            case let .primitive(primitive):
                try validatePrimitiveExpressions(
                    primitive,
                    using: parameters,
                    tolerance: tolerance
                )
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
                guard endScale.value.isFinite,
                      endScale.value > tolerance.relative else {
                    throw KernelError(
                        phase: .validation,
                        code: .sweepScaleCollapse,
                        featureID: node.id,
                        residual: endScale.value,
                        tolerance: tolerance,
                        message: "Sweep end scale collapses the section at the requested relative tolerance."
                    )
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
            case let .loft(loft):
                try loft.validate()
            case let .boolean(boolean):
                try boolean.validate()
            case let .polySpline(polySpline):
                try polySpline.validate(tolerance: tolerance)
            case let .bSplineSurface(surface):
                try surface.validate(tolerance: tolerance)
            case let .patchSurface(patch):
                try patch.validate(tolerance: tolerance)
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
            case let .faceDelete(faceDelete):
                try faceDelete.validate()
            case let .faceDraft(faceDraft):
                try faceDraft.validate()
            case let .faceOffset(offset):
                try offset.validate()
                let distance = try parameters.resolvedValue(for: offset.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "faceOffset.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value != 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .faceMove(move):
                try move.validate(tolerance: tolerance)
                let distance = try parameters.resolvedValue(for: move.translation.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "faceMove.translation.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value != 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .edgeMove(move):
                try move.validate(tolerance: tolerance)
                let distance = try parameters.resolvedValue(for: move.translation.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "edgeMove.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value != 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .vertexMove(move):
                try move.validate(tolerance: tolerance)
                let distance = try parameters.resolvedValue(for: move.translation.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "vertexMove.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value != 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .linearPattern(pattern):
                try pattern.validate(tolerance: tolerance)
                let spacing = try parameters.resolvedValue(for: pattern.spacing)
                guard spacing.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "linearPattern.spacing",
                        expected: .length,
                        actual: spacing.kind
                    )
                }
                guard spacing.value.isFinite, spacing.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(spacing.value)
                }
            case let .radialPattern(pattern):
                try pattern.validate(tolerance: tolerance)
                let spacing = try parameters.resolvedValue(for: pattern.angularSpacing)
                guard spacing.kind == .angle else {
                    throw UnitError.expectedQuantity(
                        operation: "radialPattern.angularSpacing",
                        expected: .angle,
                        actual: spacing.kind
                    )
                }
                guard spacing.value.isFinite, spacing.value != 0.0 else {
                    throw KernelError(
                        phase: .validation,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Radial pattern angular spacing must be finite and nonzero."
                    )
                }
            case let .gridPattern(pattern):
                try pattern.validate(tolerance: tolerance)
                let firstSpacing = try parameters.resolvedValue(for: pattern.firstSpacing)
                let secondSpacing = try parameters.resolvedValue(for: pattern.secondSpacing)
                guard firstSpacing.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "gridPattern.firstSpacing",
                        expected: .length,
                        actual: firstSpacing.kind
                    )
                }
                guard secondSpacing.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "gridPattern.secondSpacing",
                        expected: .length,
                        actual: secondSpacing.kind
                    )
                }
                guard firstSpacing.value.isFinite, firstSpacing.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(firstSpacing.value)
                }
                guard secondSpacing.value.isFinite, secondSpacing.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(secondSpacing.value)
                }
            case let .curveDrivenPattern(pattern):
                try pattern.validate(tolerance: tolerance)
            case let .chamfer(chamfer):
                try chamfer.validate()
                let distance = try parameters.resolvedValue(for: chamfer.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "chamfer.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .fillet(fillet):
                try fillet.validate()
                let radius = try parameters.resolvedValue(for: fillet.radius)
                guard radius.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "fillet.radius",
                        expected: .length,
                        actual: radius.kind
                    )
                }
                guard radius.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(radius.value)
                }
            case let .g2Blend(blend):
                try blend.validate()
                let distance = try parameters.resolvedValue(for: blend.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "g2Blend.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .setbackCorner(corner):
                try corner.validate()
                let radius = try parameters.resolvedValue(for: corner.radius)
                guard radius.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "setbackCorner.radius",
                        expected: .length,
                        actual: radius.kind
                    )
                }
                guard radius.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(radius.value)
                }
            case let .shell(shell):
                try shell.validate()
                let thickness = try parameters.resolvedValue(for: shell.thickness)
                guard thickness.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "shell.thickness",
                        expected: .length,
                        actual: thickness.kind
                    )
                }
                guard thickness.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(thickness.value)
                }
            case let .thicken(thicken):
                try thicken.validate()
                let thickness = try parameters.resolvedValue(for: thicken.thickness)
                guard thickness.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "thicken.thickness",
                        expected: .length,
                        actual: thickness.kind
                    )
                }
                guard thickness.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(thickness.value)
                }
            case let .bridgeCurve(bridgeCurve):
                try bridgeCurve.validate(tolerance: tolerance)
            case let .bridgeSurface(bridgeSurface):
                try bridgeSurface.validate(tolerance: tolerance)
            case let .curveEdit(curveEdit):
                try curveEdit.validate(tolerance: tolerance)
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
                try curveTrim.validate(tolerance: tolerance)
            case let .curveExtend(extensionRequest):
                try extensionRequest.validate()
                let distance = try parameters.resolvedValue(for: extensionRequest.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "curveExtend.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .curveMatch(match):
                try match.validate()
            case let .surfaceOffset(offset):
                try offset.validate()
                let distance = try parameters.resolvedValue(for: offset.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "surfaceOffset.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value.isFinite, distance.value != 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            case let .surfaceTrim(trim):
                try trim.validate(tolerance: tolerance)
            case let .surfaceExtend(extensionRequest):
                try extensionRequest.validate()
                let expressions = extensionRequest.distances
                let values = try [expressions.lowerU, expressions.upperU, expressions.lowerV, expressions.upperV].map {
                    try parameters.resolvedValue(for: $0)
                }
                for value in values {
                    guard value.kind == .length else {
                        throw UnitError.expectedQuantity(operation: "surfaceExtend.distance", expected: .length, actual: value.kind)
                    }
                    guard value.value.isFinite, value.value >= 0.0 else {
                        throw FeatureEvaluationError.invalidDistance(value.value)
                    }
                }
                guard values.contains(where: { $0.value > 0.0 }) else {
                    throw FeatureEvaluationError.invalidDistance(0.0)
                }
            case let .surfaceMatch(match):
                try match.validate()
        }
    }

    private func validatePrimitiveExpressions(
        _ feature: PrimitiveFeature,
        using parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws {
        try feature.validate(tolerance: tolerance)
        func positiveLength(_ expression: CADExpression, name: String) throws -> Double {
            let quantity = try parameters.resolvedValue(for: expression)
            guard quantity.kind == .length else {
                throw UnitError.expectedQuantity(
                    operation: name,
                    expected: .length,
                    actual: quantity.kind
                )
            }
            guard quantity.value.isFinite, quantity.value > 0.0 else {
                throw FeatureEvaluationError.invalidDistance(quantity.value)
            }
            return quantity.value
        }
        switch feature.definition {
        case let .box(primitive):
            _ = try positiveLength(primitive.width, name: "primitive.box.width")
            _ = try positiveLength(primitive.depth, name: "primitive.box.depth")
            _ = try positiveLength(primitive.height, name: "primitive.box.height")
        case let .cylinder(primitive):
            _ = try positiveLength(primitive.radius, name: "primitive.cylinder.radius")
            _ = try positiveLength(primitive.height, name: "primitive.cylinder.height")
        case let .cone(primitive):
            _ = try positiveLength(primitive.baseRadius, name: "primitive.cone.baseRadius")
            _ = try positiveLength(primitive.height, name: "primitive.cone.height")
        case let .sphere(primitive):
            _ = try positiveLength(primitive.radius, name: "primitive.sphere.radius")
        case let .torus(primitive):
            let majorRadius = try positiveLength(
                primitive.majorRadius,
                name: "primitive.torus.majorRadius"
            )
            let minorRadius = try positiveLength(
                primitive.minorRadius,
                name: "primitive.torus.minorRadius"
            )
            guard majorRadius > minorRadius else {
                throw FeatureEvaluationError.invalidGraph(
                    "Primitive torus major radius must exceed its minor radius."
                )
            }
        }
    }

    func validateOperationContract(for node: FeatureNode, tolerance: ModelingTolerance) throws {
        guard Set(node.inputs).count == node.inputs.count else {
            throw FeatureEvaluationError.invalidGraph("Feature inputs contain duplicate references.")
        }
        let outputRoles = node.outputs.map(\.role)
        guard Set(outputRoles).count == outputRoles.count else {
            throw FeatureEvaluationError.invalidGraph("Feature outputs contain duplicate roles.")
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
        case let .primitive(primitive):
            try primitive.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Primitive features must not declare inputs.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Primitive features must declare one body output.")
            }
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
        case let .loft(loft):
            try loft.validate()
            let expectedInputs = loft.sections.map { section in
                FeatureInput(featureID: section.featureID, role: .profile)
            } + loft.guides.map { guide in
                FeatureInput(featureID: guide.featureID, role: .guide)
            }
            guard Set(node.inputs) == Set(expectedInputs),
                  node.inputs.count == expectedInputs.count else {
                throw FeatureEvaluationError.invalidGraph("Loft features must consume the declared profile section and guide inputs.")
            }
            for section in loft.sections {
                guard let source = nodes[section.featureID],
                      source.outputs.contains(where: { $0.role == .profile }) else {
                    throw FeatureEvaluationError.invalidGraph("Loft section source must declare a profile output.")
                }
            }
            for guide in loft.guides {
                guard let source = nodes[guide.featureID],
                      source.outputs.contains(where: { $0.role == .curve }) else {
                    throw FeatureEvaluationError.invalidGraph("Loft guide source must declare a curve output.")
                }
            }
            switch loft.options.resultKind {
            case .solid:
                guard outputRoles == [.body] else {
                    throw FeatureEvaluationError.invalidGraph("Solid loft features must declare one body output.")
                }
            case .sheet:
                guard outputRoles == [.sheet] else {
                    throw FeatureEvaluationError.invalidGraph("Sheet loft features must declare one sheet output.")
                }
            }
        case let .boolean(boolean):
            try boolean.validate()
            let expectedInputs = boolean.targets.map { target in
                FeatureInput(featureID: target.featureID, role: .target)
            } + [
                FeatureInput(featureID: boolean.tool.featureID, role: .body)
            ]
            guard Set(node.inputs) == Set(expectedInputs),
                  node.inputs.count == expectedInputs.count else {
                throw FeatureEvaluationError.invalidGraph("Boolean features must consume declared target and tool body inputs.")
            }
            for target in boolean.targets {
                guard let targetSource = nodes[target.featureID],
                      targetSource.outputs.contains(where: { $0.role == .body }) else {
                    throw FeatureEvaluationError.invalidGraph("Boolean target source must declare a body output.")
                }
            }
            guard let toolSource = nodes[boolean.tool.featureID],
                  toolSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Boolean tool source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Boolean features must declare one body output.")
            }
        case let .polySpline(polySpline):
            try polySpline.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("PolySpline features must not declare inputs in the inline mesh subset.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("PolySpline features must declare one sheet output.")
            }
        case let .bSplineSurface(surface):
            try surface.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("B-spline surface features must not declare inputs.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("B-spline surface features must declare one sheet output.")
            }
        case let .patchSurface(patch):
            try patch.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Patch surface inline boundaries must not declare inputs.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Patch surface features must declare one sheet output.")
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
        case let .faceDelete(faceDelete):
            try faceDelete.validate()
            guard node.inputs == [FeatureInput(featureID: faceDelete.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face Delete features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[faceDelete.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face Delete target source must declare a body output.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Face Delete features must declare one sheet output.")
            }
        case let .faceDraft(faceDraft):
            try faceDraft.validate()
            guard node.inputs == [FeatureInput(featureID: faceDraft.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face Draft features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[faceDraft.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face Draft target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Face Draft features must declare one body output.")
            }
        case let .faceOffset(offset):
            try offset.validate()
            guard node.inputs == [FeatureInput(featureID: offset.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face offset features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[offset.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face offset target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Face offset features must declare one body output.")
            }
        case let .faceMove(move):
            try move.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Face move features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[move.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Face move target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Face move features must declare one body output.")
            }
        case let .edgeMove(move):
            try move.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Edge move features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[move.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Edge move target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Edge move features must declare one body output.")
            }
        case let .vertexMove(move):
            try move.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Vertex move features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[move.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Vertex move target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Vertex move features must declare one body output.")
            }
        case let .linearPattern(pattern):
            try pattern.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: pattern.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Linear pattern features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[pattern.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Linear pattern target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Linear pattern features must declare one body output.")
            }
        case let .radialPattern(pattern):
            try pattern.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: pattern.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Radial pattern features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[pattern.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Radial pattern target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Radial pattern features must declare one body output.")
            }
        case let .gridPattern(pattern):
            try pattern.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: pattern.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Grid pattern features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[pattern.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Grid pattern target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Grid pattern features must declare one body output.")
            }
        case let .curveDrivenPattern(pattern):
            try pattern.validate(tolerance: tolerance)
            guard node.inputs == [
                FeatureInput(featureID: pattern.target.featureID, role: .target),
                FeatureInput(featureID: pattern.path.featureID, role: .path),
            ] else {
                throw FeatureEvaluationError.invalidGraph("Curve-driven pattern features must consume target body and path curve inputs.")
            }
            guard let targetSource = nodes[pattern.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Curve-driven pattern target source must declare a body output.")
            }
            guard let pathSource = nodes[pattern.path.featureID],
                  pathSource.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve-driven pattern path source must declare a curve output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Curve-driven pattern features must declare one body output.")
            }
        case let .chamfer(chamfer):
            try chamfer.validate()
            guard node.inputs == [FeatureInput(featureID: chamfer.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Chamfer features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[chamfer.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Chamfer target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Chamfer features must declare one body output.")
            }
        case let .fillet(fillet):
            try fillet.validate()
            guard node.inputs == [FeatureInput(featureID: fillet.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Fillet features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[fillet.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Fillet target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Fillet features must declare one body output.")
            }
        case let .g2Blend(blend):
            try blend.validate()
            guard node.inputs == [FeatureInput(featureID: blend.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("G2 blend features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[blend.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("G2 blend target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("G2 blend features must declare one body output.")
            }
        case let .setbackCorner(corner):
            try corner.validate()
            guard node.inputs == [FeatureInput(featureID: corner.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Setback corner features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[corner.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Setback corner target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Setback corner features must declare one body output.")
            }
        case let .shell(shell):
            try shell.validate()
            guard node.inputs == [FeatureInput(featureID: shell.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Shell features must consume the referenced target body input.")
            }
            guard let targetSource = nodes[shell.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .body }) else {
                throw FeatureEvaluationError.invalidGraph("Shell target source must declare a body output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Shell features must declare one body output.")
            }
        case let .thicken(thicken):
            try thicken.validate()
            guard node.inputs == [FeatureInput(featureID: thicken.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Thicken features must consume the referenced target sheet input.")
            }
            guard let targetSource = nodes[thicken.target.featureID],
                  targetSource.outputs.contains(where: { $0.role == .sheet }) else {
                throw FeatureEvaluationError.invalidGraph("Thicken target source must declare a sheet output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Thicken features must declare one body output.")
            }
        case let .bridgeCurve(bridgeCurve):
            try bridgeCurve.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Bridge curve features currently use inline endpoint constraints and must not declare inputs.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Bridge curve features must declare one curve output.")
            }
        case let .bridgeSurface(bridgeSurface):
            try bridgeSurface.validate(tolerance: tolerance)
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Bridge surface inline boundaries must not declare inputs.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Bridge surface features must declare one sheet output.")
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
        case let .curveExtend(extensionRequest):
            try extensionRequest.validate()
            guard node.inputs == [FeatureInput(featureID: extensionRequest.source.featureID, role: .curve)] else {
                throw FeatureEvaluationError.invalidGraph("Curve extend features must consume the referenced curve input.")
            }
            guard let source = nodes[extensionRequest.source.featureID],
                  source.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve extend source must declare a curve output.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Curve extend features must declare one curve output.")
            }
        case let .curveMatch(match):
            try match.validate()
            guard node.inputs == [
                FeatureInput(featureID: match.source.featureID, role: .curve),
                FeatureInput(featureID: match.target.featureID, role: .target),
            ] else {
                throw FeatureEvaluationError.invalidGraph("Curve match features must consume source and target curve inputs.")
            }
            guard let source = nodes[match.source.featureID],
                  source.outputs.contains(where: { $0.role == .curve }),
                  let target = nodes[match.target.featureID],
                  target.outputs.contains(where: { $0.role == .curve }) else {
                throw FeatureEvaluationError.invalidGraph("Curve match inputs must declare curve outputs.")
            }
            guard outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Curve match features must declare one curve output.")
            }
        case let .surfaceOffset(offset):
            try offset.validate()
            guard node.inputs == [FeatureInput(featureID: offset.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Surface offset features must consume the referenced sheet input.")
            }
            guard let source = nodes[offset.target.featureID],
                  source.outputs.contains(where: { $0.role == .sheet }) else {
                throw FeatureEvaluationError.invalidGraph("Surface offset source must declare a sheet output.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Surface offset features must declare one sheet output.")
            }
        case let .surfaceTrim(trim):
            try trim.validate(tolerance: tolerance)
            guard node.inputs == [FeatureInput(featureID: trim.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Surface trim features must consume the referenced sheet input.")
            }
            guard let source = nodes[trim.target.featureID], source.outputs.contains(where: { $0.role == .sheet }) else {
                throw FeatureEvaluationError.invalidGraph("Surface trim source must declare a sheet output.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Surface trim features must declare one sheet output.")
            }
        case let .surfaceExtend(extensionRequest):
            try extensionRequest.validate()
            guard node.inputs == [FeatureInput(featureID: extensionRequest.target.featureID, role: .target)] else {
                throw FeatureEvaluationError.invalidGraph("Surface extend features must consume the referenced sheet input.")
            }
            guard let source = nodes[extensionRequest.target.featureID], source.outputs.contains(where: { $0.role == .sheet }) else {
                throw FeatureEvaluationError.invalidGraph("Surface extend source must declare a sheet output.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Surface extend features must declare one sheet output.")
            }
        case let .surfaceMatch(match):
            try match.validate()
            guard node.inputs == [
                FeatureInput(featureID: match.source.featureID, role: .sheet),
                FeatureInput(featureID: match.target.featureID, role: .target),
            ] else {
                throw FeatureEvaluationError.invalidGraph("Surface match features must consume source and target sheet inputs.")
            }
            guard let source = nodes[match.source.featureID],
                  source.outputs.contains(where: { $0.role == .sheet }),
                  let target = nodes[match.target.featureID],
                  target.outputs.contains(where: { $0.role == .sheet }) else {
                throw FeatureEvaluationError.invalidGraph("Surface match inputs must declare sheet outputs.")
            }
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Surface match features must declare one sheet output.")
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

    private enum CodingKeys: String, CodingKey {
        case source
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .target], in: decoder)
        source = try container.decode(FeatureID.self, forKey: .source)
        target = try container.decode(FeatureID.self, forKey: .target)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(target, forKey: .target)
    }
}
