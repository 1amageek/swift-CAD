import CADCore
import CADTopology

public struct DesignGraph: Codable, Equatable, Sendable {
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
            case let .involuteGear(gear):
                _ = try gear.resolvedDimensions { try parameters.resolvedValue(for: $0) }
            case .spatialPath:
                break
            case let .sketch(sketch):
                try sketch.validateExpressions(using: parameters)
            case .importedBRep:
                break
            case let .primitive(primitive):
                try validatePrimitiveExpressions(
                    primitive,
                    using: parameters,
                    tolerance: tolerance
                )
            case let .extrude(extrude):
                _ = try extrude.resolvedAxialRange(tolerance: tolerance) {
                    try parameters.resolvedValue(for: $0)
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
                try sweep.options.validate()
                if let expression = sweep.options.approximationTolerance {
                    let allowance = try parameters.resolvedValue(for: expression)
                    guard allowance.kind == .length, allowance.value.isFinite, allowance.value > 0 else {
                        throw FeatureEvaluationError.invalidGraph("Sweep approximation tolerance must resolve to a finite positive length.")
                    }
                }
                let twistAngle = try parameters.resolvedValue(for: sweep.options.twistAngle)
                guard twistAngle.kind == .angle else {
                    throw UnitError.expectedQuantity(
                        operation: "sweep.options.twistAngle",
                        expected: .angle,
                        actual: twistAngle.kind
                    )
                }
                let endScale = try parameters.resolvedValue(for: sweep.options.endScale)
                if let law = sweep.options.twistLaw {
                    let angles = try law.map { try parameters.resolvedValue(for: $0.angle) }
                    guard angles.allSatisfy({ $0.kind == .angle && $0.value.isFinite }),
                          angles.first?.value == 0, angles.last?.value == twistAngle.value else {
                        throw FeatureEvaluationError.invalidGraph("Sweep law must contain finite angles starting at zero and ending at twistAngle.")
                    }
                }
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
            case let .edgeCurve(edgeCurve):
                try edgeCurve.validate()
            case let .squareSurface(square):
                try square.validate()
            case let .pipe(pipe):
                try pipe.validate()
                func resolved(_ expression: CADExpression, _ kind: QuantityKind, _ name: String) throws -> Double {
                    let value = try parameters.resolvedValue(for: expression)
                    guard value.kind == kind, value.value.isFinite else {
                        throw UnitError.expectedQuantity(operation: "pipe.\(name)", expected: kind, actual: value.kind)
                    }
                    return value.value
                }
                let diameter = try pipe.diameter.map { try resolved($0, .length, "diameter") }
                let thickness = try pipe.thickness.map { try resolved($0, .length, "thickness") }
                let start = try resolved(pipe.start, .scalar, "start")
                let end = try resolved(pipe.end, .scalar, "end")
                _ = try resolved(pipe.angle, .angle, "angle")
                let endScale = try resolved(pipe.endScale, .scalar, "endScale")
                let allowance = try resolved(pipe.approximationTolerance, .length, "approximationTolerance")
                // A custom profile's wall is checked against its section when it is offset.
                let diameterAdmitted = diameter.map { diameter in
                    diameter > tolerance.distance && (thickness.map { 2 * $0 < diameter } ?? true)
                } ?? true
                guard diameterAdmitted, thickness.map({ $0 > tolerance.distance }) ?? true,
                      0 <= start, start < end, end <= 1, endScale > tolerance.relative, allowance > 0 else {
                    throw FeatureEvaluationError.invalidGraph(
                        "A pipe needs a positive diameter, a wall thinner than its radius, 0 ≤ start < end ≤ 1, a positive end scale and allowance."
                    )
                }
            case let .loft(loft):
                try loft.validate()
            case let .boolean(boolean):
                try boolean.validate()
            case let .polySpline(polySpline):
                try polySpline.validate(tolerance: tolerance)
            case let .constrainedSurface(surface):
                try surface.validate(tolerance: tolerance)
            case let .bSplineSurface(surface):
                try surface.validate(tolerance: tolerance)
            case let .patchSurface(patch):
                try patch.validate(tolerance: tolerance)
            case .surfaceFill:
                break
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
                if let adjacentAngle = offset.adjacentAngle {
                    let angle = try parameters.resolvedValue(for: adjacentAngle)
                    guard angle.kind == .angle else {
                        throw UnitError.expectedQuantity(operation: "faceOffset.adjacentAngle", expected: .angle, actual: angle.kind)
                    }
                    guard angle.value.isFinite, abs(angle.value) < Double.pi / 2 else {
                        throw FeatureEvaluationError.invalidGraph("Push Face adjacent angle must lie strictly between -90 and 90 degrees.")
                    }
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
            case let .topologyTransform(transform):
                try transform.validate(tolerance: tolerance)
                let expected: QuantityKind
                switch transform.motion {
                case .translation: expected = .length
                case .rotation: expected = .angle
                case .scale: expected = .scalar
                }
                for expression in transform.motion.expressions {
                    let value = try parameters.resolvedValue(for: expression)
                    guard value.kind == expected else {
                        throw UnitError.expectedQuantity(
                            operation: "topologyTransform.motion",
                            expected: expected,
                            actual: value.kind
                        )
                    }
                    guard value.value.isFinite else {
                        throw FeatureEvaluationError.invalidDistance(value.value)
                    }
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
            case let .mirror(mirror):
                try mirror.validate(tolerance: tolerance)
            case let .joinBodies(join):
                try join.validate()
            case let .unjoinBody(unjoin):
                try unjoin.validate()
            case let .unjoinFaces(unjoin):
                try unjoin.validate()
            case let .reverseSheet(reverse):
                try reverse.validate()
            case let .isoparam(feature):
                try feature.validate()
            case let .imprintBody(feature):
                try feature.validate()
            case let .faceMatch(feature):
                try feature.validate()
            case let .removeFillets(feature):
                try feature.validate()
            case let .removeRedundantTopology(feature):
                try feature.validate()
            case let .sheetExtend(feature):
                try feature.validate()
            case let .faceRebuild(feature):
                try feature.validate()
            case let .faceUnwrap(feature):
                try feature.validate()
            case let .surfaceAlign(feature):
                try feature.validate()
            case let .untrimFace(feature):
                try feature.validate()
            case let .imprintCurves(feature):
                try feature.validate()
            case let .extract(extract):
                try extract.validate()
            case let .wrap(wrap):
                try wrap.validate()
                guard try parameters.resolvedValue(for: wrap.options.offsetN).kind == .length else {
                    throw FeatureEvaluationError.invalidGraph("Wrap N offset must be a length.")
                }
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
                let front = try parameters.resolvedValue(for: thicken.front)
                let back = try parameters.resolvedValue(for: thicken.back)
                for (side, value) in [("thicken.front", front), ("thicken.back", back)] {
                    guard value.kind == .length else {
                        throw UnitError.expectedQuantity(operation: side, expected: .length, actual: value.kind)
                    }
                    guard value.value >= 0.0 else {
                        throw FeatureEvaluationError.invalidDistance(value.value)
                    }
                }
                guard front.value + back.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(front.value + back.value)
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
            case let .projectCurve(projectCurve):
                try projectCurve.validate(tolerance: tolerance)
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
                try extensionRequest.validate(tolerance: tolerance)
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
        case let .involuteGear(gear):
            guard node.inputs.isEmpty, outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Gear source requires no feature inputs and one body output.")
            }
            try gear.validate(tolerance: tolerance)
        case let .spatialPath(path):
            guard node.inputs.isEmpty, outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Spatial paths have no inputs and exactly one curve output.")
            }
            try path.validate(tolerance: tolerance)
        case .sketch:
            try validateSketchContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .importedBRep:
            try validateImportedBRepContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .primitive:
            try validatePrimitiveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .extrude:
            try validateExtrudeContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .revolve:
            try validateRevolveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .sweep:
            try validateSweepContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .pipe:
            try validatePipeContract(node, outputRoles: outputRoles)
        case .edgeCurve:
            guard case let .edgeCurve(edgeCurve) = node.operation else {
                throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an edgeCurve operation.")
            }
            try edgeCurve.validate()
            guard node.inputs == [FeatureInput(featureID: edgeCurve.source, role: edgeCurve.bodyRole)],
                  nodes[edgeCurve.source]?.outputs.contains(where: { $0.role == edgeCurve.bodyRole }) == true,
                  outputRoles == [.curve] else {
                throw FeatureEvaluationError.invalidGraph("Edge curves consume their body and declare one curve output.")
            }
        case .squareSurface:
            guard case let .squareSurface(square) = node.operation else {
                throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a squareSurface operation.")
            }
            try square.validate()
            guard node.inputs == square.inputs,
                  square.inputs.allSatisfy({ input in nodes[input.featureID]?.outputs.contains(where: { $0.role == input.role }) == true }),
                  outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("A Square consumes its side curves and continuity bodies and declares one sheet output.")
            }
        case .loft:
            try validateLoftContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .boolean:
            try validateBooleanContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .polySpline:
            try validatePolySplineContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .constrainedSurface(let surface):
            try surface.validate(tolerance: tolerance)
            guard node.inputs.isEmpty, outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Constrained Surface requires no inputs and one Sheet output.")
            }
        case .bSplineSurface:
            try validateBSplineSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .patchSurface:
            try validatePatchSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .surfaceFill:
            try validateSurfaceFillContract(node, outputRoles: outputRoles)
        case .faceLoopOffset:
            try validateFaceLoopOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .edgeOffset:
            try validateEdgeOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .faceKnife:
            try validateFaceKnifeContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .faceDelete:
            try validateFaceDeleteContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .faceDraft:
            try validateFaceDraftContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .faceOffset:
            try validateFaceOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .faceMove:
            try validateFaceMoveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .edgeMove:
            try validateEdgeMoveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .vertexMove:
            try validateVertexMoveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .topologyTransform:
            try validateTopologyTransformContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .linearPattern:
            try validateLinearPatternContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .radialPattern:
            try validateRadialPatternContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .gridPattern:
            try validateGridPatternContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveDrivenPattern:
            try validateCurveDrivenPatternContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .mirror:
            try validateMirrorContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .joinBodies:
            try validateJoinBodiesContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .unjoinBody:
            try validateUnjoinBodyContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .unjoinFaces:
            try validateUnjoinFacesContract(node, outputRoles: outputRoles)
        case .reverseSheet:
            try validateReverseSheetContract(node, outputRoles: outputRoles)
        case .isoparam, .imprintBody, .untrimFace, .imprintCurves:
            try validateImprintContract(node, outputRoles: outputRoles)
        case .faceMatch:
            try validateFaceMatchContract(node, outputRoles: outputRoles)
        case .removeFillets:
            try validateRemoveFilletsContract(node, outputRoles: outputRoles)
        case .removeRedundantTopology:
            try validateRemoveRedundantTopologyContract(node, outputRoles: outputRoles)
        case .sheetExtend:
            try validateSheetExtendContract(node, outputRoles: outputRoles)
        case .faceRebuild:
            try validateFaceRebuildContract(node, outputRoles: outputRoles)
        case .faceUnwrap:
            try validateFaceUnwrapContract(node, outputRoles: outputRoles)
        case .surfaceAlign:
            try validateSurfaceAlignContract(node, outputRoles: outputRoles)
        case .extract:
            try validateExtractContract(node, outputRoles: outputRoles)
        case .wrap:
            try validateWrapContract(node, outputRoles: outputRoles)
        case .chamfer:
            try validateChamferContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .fillet:
            try validateFilletContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .g2Blend:
            try validateG2BlendContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .setbackCorner:
            try validateSetbackCornerContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .shell:
            try validateShellContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .thicken:
            try validateThickenContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .bridgeCurve:
            try validateBridgeCurveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .bridgeSurface:
            try validateBridgeSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveEdit:
            try validateCurveEditContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveOffset:
            try validateCurveOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .projectCurve:
            try validateProjectCurveContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveTrim:
            try validateCurveTrimContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveExtend:
            try validateCurveExtendContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .curveMatch:
            try validateCurveMatchContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .surfaceOffset:
            try validateSurfaceOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .surfaceTrim:
            try validateSurfaceTrimContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .surfaceExtend:
            try validateSurfaceExtendContract(node, outputRoles: outputRoles, tolerance: tolerance)
        case .surfaceMatch:
            try validateSurfaceMatchContract(node, outputRoles: outputRoles, tolerance: tolerance)
        }
    }

    @inline(never)
    private func validateSketchContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .sketch(sketch) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sketch operation.")
        }
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Sketch features must not declare inputs.")
        }
        let allowedSketchOutputs: Set<FeaturePort> = [.profile, .curve]
        guard outputRoles.isEmpty == false,
              Set(outputRoles).isSubset(of: allowedSketchOutputs) else {
            throw FeatureEvaluationError.invalidGraph("Sketch features must declare profile or curve outputs.")
        }
        try sketch.validate(tolerance: tolerance)
    }

    @inline(never)
    private func validatePrimitiveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .primitive(primitive) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a primitive operation.")
        }
        try primitive.validate(tolerance: tolerance)
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Primitive features must not declare inputs.")
        }
        guard outputRoles == [.body] else {
            throw FeatureEvaluationError.invalidGraph("Primitive features must declare one body output.")
        }
    }

    @inline(never)
    private func validateImportedBRepContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .importedBRep(importedBRep) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an imported B-rep operation.")
        }
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Imported B-rep features must not declare inputs.")
        }
        try importedBRep.validate(tolerance: tolerance)
        let expectedRole: FeaturePort = importedBRep.model.bodies.values.first?.kind == .solid
            ? .body
            : .sheet
        guard outputRoles == [expectedRole] else {
            throw FeatureEvaluationError.invalidGraph(
                "Imported B-rep features must declare one \(expectedRole.rawValue) output."
            )
        }
    }

    @inline(never)
    private func validateExtrudeContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .extrude(extrude) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a extrude operation.")
        }
        try extrude.validate()
        guard node.inputs == [FeatureInput(featureID: extrude.section.featureID, role: extrude.section.inputRole)]
            + extrude.targets.map({ FeatureInput(featureID: $0.featureID, role: .target) }) else {
            throw FeatureEvaluationError.invalidGraph("Extrude features must consume the referenced section input.")
        }
        guard let source = nodes[extrude.section.featureID],
              source.outputs.contains(where: { $0.role == extrude.section.inputRole }) else {
            throw FeatureEvaluationError.invalidGraph("Extrude source must declare the section input role.")
        }
        for target in extrude.targets {
            guard nodes[target.featureID]?.outputs.contains(where: { $0.role == .body }) == true else {
                throw FeatureEvaluationError.invalidGraph("Extrude Boolean target must declare a solid body output.")
            }
        }
        switch extrude.resultKind {
        case .solid:
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Solid extrude features must declare one body output.")
            }
        case .sheet:
            guard outputRoles == [.sheet] else {
                throw FeatureEvaluationError.invalidGraph("Sheet extrude features must declare one sheet output.")
            }
        }
        if case let .vector(vector) = extrude.direction {
            try vector.validate()
        }
    }

    @inline(never)
    private func validateRevolveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .revolve(revolve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a revolve operation.")
        }
        try revolve.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: revolve.section.featureID, role: revolve.section.inputRole)]
            + revolve.targets.map({ FeatureInput(featureID: $0.featureID, role: .target) }) else {
            throw FeatureEvaluationError.invalidGraph("Revolve features must consume the referenced section and target inputs.")
        }
        guard let source = nodes[revolve.section.featureID],
              source.outputs.contains(where: { $0.role == revolve.section.inputRole }) else {
            throw FeatureEvaluationError.invalidGraph("Revolve source must declare the section input role.")
        }
        for target in revolve.targets {
            guard nodes[target.featureID]?.outputs.contains(where: { $0.role == .body }) == true else {
                throw FeatureEvaluationError.invalidGraph("Revolve Boolean target must declare a solid body output.")
            }
        }
        guard outputRoles == [revolve.resultKind == .solid ? .body : .sheet] else {
            throw FeatureEvaluationError.invalidGraph("Revolve output must agree with its body kind.")
        }
    }

    @inline(never)
    private func validatePipeContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .pipe(pipe) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a pipe operation.")
        }
        try pipe.validate()
        guard node.inputs == pipe.inputs else {
            throw FeatureEvaluationError.invalidGraph("Pipe features must consume their profile, path and target inputs.")
        }
        if let profile = pipe.profile {
            guard nodes[profile.featureID]?.outputs.contains(where: { $0.role == profile.inputRole }) == true else {
                throw FeatureEvaluationError.invalidGraph("Pipe profile source must declare a \(profile.inputRole.rawValue) output.")
            }
        }
        guard nodes[pipe.path.featureID]?.outputs.contains(where: { $0.role == .curve }) == true else {
            throw FeatureEvaluationError.invalidGraph("Pipe path source must declare a curve output.")
        }
        for target in pipe.targets {
            guard nodes[target.featureID]?.outputs.contains(where: { $0.role == .body }) == true else {
                throw FeatureEvaluationError.invalidGraph("Pipe target source must declare a body output.")
            }
        }
        guard outputRoles == [.body] else {
            throw FeatureEvaluationError.invalidGraph("Pipe features declare one body output.")
        }
    }

    @inline(never)
    private func validateSweepContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .sweep(sweep) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sweep operation.")
        }
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
    }

    @inline(never)
    private func validateLoftContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .loft(loft) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a loft operation.")
        }
        try loft.validate()
        let expectedInputs = loft.inputs
        guard Set(node.inputs) == Set(expectedInputs),
              node.inputs.count == expectedInputs.count else {
            throw FeatureEvaluationError.invalidGraph("Loft features must consume the declared section and guide inputs.")
        }
        for section in loft.sections {
            for input in section.inputs {
                guard let source = nodes[input.featureID], source.outputs.contains(where: { $0.role == input.role }) else {
                    throw FeatureEvaluationError.invalidGraph("Loft section source must declare its requested output kind.")
                }
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
    }

    @inline(never)
    private func validateBooleanContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .boolean(boolean) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a boolean operation.")
        }
        try boolean.validate()
        let expectedInputs = boolean.targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        } + boolean.tools.map { tool in
            FeatureInput(featureID: tool.featureID, role: .body)
        }
        guard Set(node.inputs) == Set(expectedInputs),
              node.inputs.count == expectedInputs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean features must consume declared target and tool body inputs.")
        }
        let targetPorts = try boolean.targets.map { target -> FeaturePort in
            guard let port = nodes[target.featureID]?.bodyOrSheetOutput else {
                throw FeatureEvaluationError.invalidGraph("Boolean target source must declare a body or sheet output.")
            }
            return port
        }
        for tool in boolean.tools {
            guard nodes[tool.featureID]?.bodyOrSheetOutput != nil else {
                throw FeatureEvaluationError.invalidGraph("Boolean tool source must declare a body or sheet output.")
            }
        }
        guard outputRoles == [try boolean.resultPort(targetPorts: targetPorts)] else {
            throw FeatureEvaluationError.invalidGraph("Boolean features must declare the one output their targets and material give.")
        }
    }

    @inline(never)
    private func validatePolySplineContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .polySpline(polySpline) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a polySpline operation.")
        }
        try polySpline.validate(tolerance: tolerance)
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("PolySpline features must not declare inputs in the inline mesh subset.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("PolySpline features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validateBSplineSurfaceContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .bSplineSurface(surface) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bSplineSurface operation.")
        }
        try surface.validate(tolerance: tolerance)
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface features must not declare inputs.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validatePatchSurfaceContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .patchSurface(patch) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a patchSurface operation.")
        }
        try patch.validate(tolerance: tolerance)
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Patch surface inline boundaries must not declare inputs.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Patch surface features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validateSurfaceFillContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort]
    ) throws {
        guard case let .surfaceFill(fill) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceFill operation.")
        }
        try fill.validate()
        guard node.inputs == [FeatureInput(featureID: fill.targetFeatureID, role: .target)],
              let source = nodes[fill.targetFeatureID],
              source.outputs.filter({ $0.role == .body || $0.role == .sheet }).count == 1,
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Surface fill requires one body target input and one sheet output.")
        }
    }

    @inline(never)
    private func validateFaceLoopOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceLoopOffset(faceLoopOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceLoopOffset operation.")
        }
        try faceLoopOffset.validate()
        guard node.inputs == [FeatureInput(featureID: faceLoopOffset.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Face loop offset features must consume the referenced target body input.")
        }
        guard let targetPort = nodes[faceLoopOffset.target.featureID]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("Face loop offset target source must declare one body or sheet output.")
        }
        guard outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Face loop offset features must declare their target's body or sheet output.")
        }
    }

    @inline(never)
    private func validateEdgeOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .edgeOffset(edgeOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a edgeOffset operation.")
        }
        try edgeOffset.validate()
        guard node.inputs == [FeatureInput(featureID: edgeOffset.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Edge offset features must consume the referenced target body input.")
        }
        guard let targetPort = nodes[edgeOffset.target.featureID]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("Edge offset target source must declare one body or sheet output.")
        }
        guard outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Edge offset features must declare their target's body or sheet output.")
        }
    }

    @inline(never)
    private func validateFaceKnifeContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceKnife(faceKnife) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceKnife operation.")
        }
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
    }

    @inline(never)
    private func validateFaceDeleteContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceDelete(faceDelete) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceDelete operation.")
        }
        try faceDelete.validate()
        guard node.inputs == [FeatureInput(featureID: faceDelete.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Face Delete features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[faceDelete.target.featureID],
              targetSource.outputs.contains(where: { $0.role == .body }) else {
            throw FeatureEvaluationError.invalidGraph("Face Delete target source must declare a body output.")
        }
        guard outputRoles == [faceDelete.outputRole] else {
            throw FeatureEvaluationError.invalidGraph("Face Delete features must declare one sheet output, or one body output when they heal.")
        }
    }

    @inline(never)
    private func validateFaceDraftContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceDraft(faceDraft) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceDraft operation.")
        }
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
    }

    @inline(never)
    private func validateFaceOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceOffset(offset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceOffset operation.")
        }
        try offset.validate()
        guard node.inputs == [FeatureInput(featureID: offset.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Face offset features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[offset.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Face offset target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Face offset target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Face offset features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateFaceMoveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .faceMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceMove operation.")
        }
        try move.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Face move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Face move target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Face move target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Face move features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateEdgeMoveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .edgeMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a edgeMove operation.")
        }
        try move.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Edge move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Edge move target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Edge move target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Edge move features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateVertexMoveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .vertexMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a vertexMove operation.")
        }
        try move.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: move.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Vertex move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Vertex move target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Vertex move target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Vertex move features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateTopologyTransformContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .topologyTransform(transform) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a topologyTransform operation.")
        }
        try transform.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: transform.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Topology transform features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[transform.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Topology transform target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Topology transform target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Topology transform features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateLinearPatternContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .linearPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a linearPattern operation.")
        }
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
    }

    @inline(never)
    private func validateRadialPatternContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .radialPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a radialPattern operation.")
        }
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
    }

    @inline(never)
    private func validateGridPatternContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .gridPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a gridPattern operation.")
        }
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
    }

    @inline(never)
    private func validateCurveDrivenPatternContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveDrivenPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveDrivenPattern operation.")
        }
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
    }

    @inline(never)
    private func validateMirrorContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .mirror(mirror) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a mirror operation.")
        }
        try mirror.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: mirror.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Mirror features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[mirror.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Mirror target source must declare a body or sheet output.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter { $0 == .body || $0 == .sheet }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph("Mirror target source must declare a body or sheet output.")
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph("Mirror features must declare the output role of their target.")
        }
    }

    @inline(never)
    private func validateJoinBodiesContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .joinBodies(join) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a joinBodies operation.")
        }
        try join.validate()
        let expectedInputs = join.targets.map { target in
            FeatureInput(featureID: target.featureID, role: .target)
        }
        guard node.inputs == expectedInputs else {
            throw FeatureEvaluationError.invalidGraph("Join bodies features must consume the referenced target body inputs.")
        }
        for target in join.targets {
            guard let targetSource = nodes[target.featureID],
                  targetSource.outputs.contains(where: { $0.role == join.mode.targetPort }) else {
                throw FeatureEvaluationError.invalidGraph(
                    "Join bodies target source must declare a \(join.mode.targetPort.rawValue) output."
                )
            }
        }
        guard outputRoles == [join.mode.outputPort] else {
            throw FeatureEvaluationError.invalidGraph(
                "Join bodies features must declare one \(join.mode.outputPort.rawValue) output."
            )
        }
    }

    @inline(never)
    private func validateWrapContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .wrap(wrap) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a wrap operation.")
        }
        try wrap.validate()
        guard node.inputs == wrap.sourceInputs else {
            throw FeatureEvaluationError.invalidGraph("Wrap must consume its target and the owners of its reference and target faces.")
        }
        guard let sourcePort = nodes[wrap.target.featureID]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("Wrap target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [try wrap.resultPort(sourcePort: sourcePort)] else {
            throw FeatureEvaluationError.invalidGraph("Wrap features must declare their target's output.")
        }
    }

    private func validateExtractContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .extract(extract) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an extract operation.")
        }
        try extract.validate()
        guard node.inputs == [FeatureInput(featureID: extract.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Extract features must consume the referenced target input.")
        }
        guard let sourcePort = nodes[extract.target.featureID]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("Extract target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [try extract.resultPort(sourcePort: sourcePort)] else {
            throw FeatureEvaluationError.invalidGraph("Extract features must declare the one output their selection gives.")
        }
    }

    private func validateUnjoinFacesContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .unjoinFaces(unjoin) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an unjoinFaces operation.")
        }
        try unjoin.validate()
        guard node.inputs == [FeatureInput(featureID: unjoin.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces features must consume the referenced target input.")
        }
        guard nodes[unjoin.target.featureID]?.bodyOrSheetOutput != nil else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces features must declare one sheet output.")
        }
    }

    /// Align Surface consumes its sheet, reads the reference's body, and publishes a sheet.
    private func validateSurfaceAlignContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .surfaceAlign(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceAlign operation.")
        }
        try feature.validate()
        guard node.inputs == feature.inputs else {
            throw FeatureEvaluationError.invalidGraph("Align Surface features must consume exactly their referenced inputs.")
        }
        guard nodes[feature.target.featureID]?.outputs.contains(where: { $0.role == .sheet }) == true,
              nodes[feature.reference.featureID]?.bodyOrSheetOutput != nil, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Align Surface takes a sheet and publishes one.")
        }
    }

    /// Rebuild Face reshapes its target's faces and publishes its target's kind of body.
    private func validateFaceRebuildContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .faceRebuild(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceRebuild operation.")
        }
        try feature.validate()
        guard node.inputs == feature.inputs else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face features must consume exactly their target.")
        }
        guard let targetPort = nodes[feature.target.featureID]?.bodyOrSheetOutput, outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face publishes its target's kind of body.")
        }
    }

    /// Unwrap Face reads a body and publishes the flattened face as a sheet.
    private func validateFaceUnwrapContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .faceUnwrap(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceUnwrap operation.")
        }
        try feature.validate()
        guard node.inputs == feature.inputs else {
            throw FeatureEvaluationError.invalidGraph("Unwrap Face features must consume exactly their target.")
        }
        guard nodes[feature.target.featureID]?.bodyOrSheetOutput != nil, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Unwrap Face reads a body or sheet and publishes a sheet.")
        }
    }

    /// Extend Sheet reads its sheet, consuming it when the extensions join it, and publishes a sheet.
    private func validateSheetExtendContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .sheetExtend(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sheetExtend operation.")
        }
        try feature.validate()
        guard node.inputs == feature.inputs else {
            throw FeatureEvaluationError.invalidGraph("Extend Sheet features must consume exactly their referenced inputs.")
        }
        guard nodes[feature.target.featureID]?.outputs.contains(where: { $0.role == .sheet }) == true, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Extend Sheet takes a sheet and publishes one.")
        }
    }

    /// Delete Redundant Topology keeps its target's kind of body in its place.
    private func validateRemoveRedundantTopologyContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .removeRedundantTopology(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a removeRedundantTopology operation.")
        }
        try feature.validate()
        guard node.inputs == [FeatureInput(featureID: feature.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Delete Redundant Topology features must consume exactly their target.")
        }
        guard let targetPort = nodes[feature.target.featureID]?.bodyOrSheetOutput, outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Delete Redundant Topology publishes its target's kind of body.")
        }
    }

    /// Remove Fillets reshapes its solid target in its place.
    private func validateRemoveFilletsContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .removeFillets(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a removeFillets operation.")
        }
        try feature.validate()
        guard node.inputs == [FeatureInput(featureID: feature.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Remove Fillets features must consume exactly their target.")
        }
        guard nodes[feature.target.featureID]?.outputs.contains(where: { $0.role == .body }) == true, outputRoles == [.body] else {
            throw FeatureEvaluationError.invalidGraph("Remove Fillets takes a solid and publishes one.")
        }
    }

    /// Match Face reshapes its target and publishes it as the same kind of body, reading the
    /// reference face's body as well when that is another.
    private func validateFaceMatchContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .faceMatch(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceMatch operation.")
        }
        try feature.validate()
        guard node.inputs == feature.inputs else {
            throw FeatureEvaluationError.invalidGraph("Match Face features must consume exactly their referenced inputs.")
        }
        guard let targetPort = nodes[feature.target.featureID]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("Match Face target must declare one body or sheet output.")
        }
        guard nodes[feature.source.featureID]?.bodyOrSheetOutput != nil else {
            throw FeatureEvaluationError.invalidGraph("Match Face reference body must declare one body or sheet output.")
        }
        guard outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Match Face features must publish their target's kind of body.")
        }
    }

    /// Isoparam and Imprint split their target and publish it as the same kind of body; Imprint
    /// reads its tool as well; Untrim publishes a sheet beside its target.
    private func validateImprintContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        let target: FeatureID
        var inputs: [FeatureInput]
        var output: FeaturePort?
        switch node.operation {
        case let .isoparam(feature):
            try feature.validate()
            target = feature.target.featureID
            inputs = [FeatureInput(featureID: target, role: .target)]
        case let .imprintBody(feature):
            try feature.validate()
            target = feature.target.featureID
            inputs = [FeatureInput(featureID: target, role: .target), FeatureInput(featureID: feature.tool.featureID, role: .body)]
            guard nodes[feature.tool.featureID]?.bodyOrSheetOutput != nil else {
                throw FeatureEvaluationError.invalidGraph("Imprint's tool must declare one body or sheet output.")
            }
        case let .untrimFace(feature):
            try feature.validate()
            target = feature.target.featureID
            inputs = [FeatureInput(featureID: target, role: .target)]
            output = .sheet
        case let .imprintCurves(feature):
            try feature.validate()
            target = feature.target.featureID
            inputs = [FeatureInput(featureID: target, role: .target)] + feature.curveInputs
        default:
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an imprint operation.")
        }
        guard node.inputs == inputs else {
            throw FeatureEvaluationError.invalidGraph("Imprint features must consume exactly their referenced inputs.")
        }
        guard let targetPort = nodes[target]?.bodyOrSheetOutput else {
            throw FeatureEvaluationError.invalidGraph("An imprint's target must declare one body or sheet output.")
        }
        guard outputRoles == [output ?? targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Imprint features must declare the one output their operation gives.")
        }
    }

    private func validateReverseSheetContract(_ node: FeatureNode, outputRoles: [FeaturePort]) throws {
        guard case let .reverseSheet(reverse) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a reverseSheet operation.")
        }
        try reverse.validate()
        guard node.inputs == [FeatureInput(featureID: reverse.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Reverse sheet features must consume the referenced target input.")
        }
        guard nodes[reverse.target.featureID]?.bodyOrSheetOutput == .sheet else {
            throw FeatureEvaluationError.invalidGraph("Reverse sheet target source must declare one sheet output.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Reverse sheet features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validateUnjoinBodyContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .unjoinBody(unjoin) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an unjoinBody operation.")
        }
        try unjoin.validate()
        guard node.inputs == [FeatureInput(featureID: unjoin.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin body features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[unjoin.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin body target source is missing.")
        }
        let targetRoles = targetSource.outputs.map(\.role).filter {
            $0 == .body || $0 == .sheet
        }
        guard targetRoles.count == 1, let targetRole = targetRoles.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Unjoin body target source must declare exactly one body or sheet output."
            )
        }
        guard outputRoles == [targetRole] else {
            throw FeatureEvaluationError.invalidGraph(
                "Unjoin body output must preserve the target's body or sheet role."
            )
        }
    }

    @inline(never)
    private func validateChamferContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .chamfer(chamfer) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a chamfer operation.")
        }
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
    }

    @inline(never)
    private func validateFilletContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .fillet(fillet) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a fillet operation.")
        }
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
    }

    @inline(never)
    private func validateG2BlendContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .g2Blend(blend) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a g2Blend operation.")
        }
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
    }

    @inline(never)
    private func validateSetbackCornerContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .setbackCorner(corner) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a setbackCorner operation.")
        }
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
    }

    @inline(never)
    private func validateShellContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .shell(shell) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a shell operation.")
        }
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
    }

    @inline(never)
    private func validateThickenContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .thicken(thicken) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a thicken operation.")
        }
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
    }

    @inline(never)
    private func validateBridgeCurveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .bridgeCurve(bridgeCurve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bridgeCurve operation.")
        }
        try bridgeCurve.validate(tolerance: tolerance)
        guard node.inputs == [
            FeatureInput(featureID: bridgeCurve.start.curve.featureID, role: .curve),
            FeatureInput(featureID: bridgeCurve.end.curve.featureID, role: .target),
        ] else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge curve features must consume their start and end curve references."
            )
        }
        guard let startSource = nodes[bridgeCurve.start.curve.featureID],
              startSource.outputs.contains(where: { $0.role == .curve }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge curve start source must declare a curve output."
            )
        }
        guard let endSource = nodes[bridgeCurve.end.curve.featureID],
              endSource.outputs.contains(where: { $0.role == .curve }) else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge curve end source must declare a curve output."
            )
        }
        guard outputRoles == [.curve] else {
            throw FeatureEvaluationError.invalidGraph("Bridge curve features must declare one curve output.")
        }
    }

    @inline(never)
    private func validateBridgeSurfaceContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .bridgeSurface(bridgeSurface) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bridgeSurface operation.")
        }
        try bridgeSurface.validate(tolerance: tolerance)
        guard node.inputs == bridgeSurface.sourceInputs else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface must consume every source feature owning its boundary edges."
            )
        }
        for input in bridgeSurface.sourceInputs {
            guard let source = nodes[input.featureID],
                  source.outputs.filter({ $0.role == .body || $0.role == .sheet }).count == 1 else {
                throw FeatureEvaluationError.invalidGraph(
                    "Bridge surface source must declare exactly one body or sheet output."
                )
            }
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Bridge surface features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validateCurveEditContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveEdit(curveEdit) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveEdit operation.")
        }
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
    }

    @inline(never)
    private func validateCurveOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveOffset(curveOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveOffset operation.")
        }
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
    }

    @inline(never)
    private func validateProjectCurveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .projectCurve(projectCurve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a projectCurve operation.")
        }
        try projectCurve.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: projectCurve.source.featureID, role: .curve)] else {
            throw FeatureEvaluationError.invalidGraph("Curve projection features must consume the referenced curve input.")
        }
        guard let source = nodes[projectCurve.source.featureID],
              source.outputs.contains(where: { $0.role == .curve }) else {
            throw FeatureEvaluationError.invalidGraph("Curve projection source must declare a curve output.")
        }
        guard outputRoles == [.curve] else {
            throw FeatureEvaluationError.invalidGraph("Curve projection features must declare one curve output.")
        }
    }

    @inline(never)
    private func validateCurveTrimContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveTrim(curveTrim) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveTrim operation.")
        }
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

    @inline(never)
    private func validateCurveExtendContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveExtend(extensionRequest) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveExtend operation.")
        }
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
    }

    @inline(never)
    private func validateCurveMatchContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .curveMatch(match) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveMatch operation.")
        }
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
    }

    @inline(never)
    private func validateSurfaceOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .surfaceOffset(offset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceOffset operation.")
        }
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
    }

    @inline(never)
    private func validateSurfaceTrimContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .surfaceTrim(trim) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceTrim operation.")
        }
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
    }

    @inline(never)
    private func validateSurfaceExtendContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .surfaceExtend(extensionRequest) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceExtend operation.")
        }
        try extensionRequest.validate(tolerance: tolerance)
        guard node.inputs == [FeatureInput(featureID: extensionRequest.target.featureID, role: .target)] else {
            throw FeatureEvaluationError.invalidGraph("Surface extend features must consume the referenced sheet input.")
        }
        guard let source = nodes[extensionRequest.target.featureID], source.outputs.contains(where: { $0.role == .sheet }) else {
            throw FeatureEvaluationError.invalidGraph("Surface extend source must declare a sheet output.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Surface extend features must declare one sheet output.")
        }
    }

    @inline(never)
    private func validateSurfaceMatchContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance
    ) throws {
        guard case let .surfaceMatch(match) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceMatch operation.")
        }
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
