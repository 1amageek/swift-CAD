import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

public struct DesignGraph: Equatable, Sendable {
    public var nodes: PersistentMap<FeatureID, FeatureNode>
    public var order: [FeatureID]
    public var dependencies: [DependencyEdge]
    public var revision: DocumentRevision

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case nodes
        case order
        case dependencies
        case revision
    }
#endif

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

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.materializedDictionary(), forKey: .nodes)
        try container.encode(order, forKey: .order)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(revision, forKey: .revision)
    }
#endif

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try revision.validate()
        let orderSet = (try OriginalParameterQueryStorage.set(order, using: &execution))
        guard orderSet.count == order.count else {
            throw FeatureEvaluationError.invalidGraph("Feature order contains duplicate IDs.")
        }
        guard (try OriginalParameterQueryStorage.set(dependencies, using: &execution)).count == dependencies.count else {
            throw FeatureEvaluationError.invalidGraph("Dependency edges contain duplicates.")
        }
        let nodeIDs = (try OriginalParameterQueryStorage.set(nodes.keys, using: &execution))
        guard orderSet.count == nodeIDs.count,
              try OriginalParameterQueryStorage.allSatisfy(orderSet, using: &execution, predicate: { id, execution in nodeIDs.contains(id) }) else {
            throw FeatureEvaluationError.invalidGraph("Feature order must contain every node exactly once.")
        }
        for (featureID, node) in nodes {
            try execution.consumeWork(1)
            guard node.id == featureID else {
                throw FeatureEvaluationError.invalidGraph("Feature node key does not match its ID.")
            }
            try validateOperationContract(for: node, tolerance: tolerance, using: &execution)
            for input in node.inputs {
                try execution.consumeWork(1)
                guard nodes[input.featureID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references a missing node.")
                }
            }
        }
        for dependency in dependencies {
            try execution.consumeWork(1)
            guard nodes[dependency.source] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency source is missing.")
            }
            guard nodes[dependency.target] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
        }
        try validateAcyclicDependencies(execution: &execution)
        try validateOrderRespectsDependencies(execution: &execution)
        try validateInputsAreRepresentedByDependencies(execution: &execution)
        try validateDependenciesAreRepresentedByInputs(execution: &execution)
        try validateActiveFeaturesDoNotDependOnSuppressedSources(execution: &execution)
    }

    public func validateExpressions(
        using parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateExpressions(using: parameters, tolerance: tolerance, execution: &execution)
    }

    public func validateExpressions(
        using parameters: ParameterTable,
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        for featureID in order {
            try execution.consumeWork(1)
            guard let node = nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            try validateExpressions(for: node, using: parameters, tolerance: tolerance, execution: &execution)
        }
    }

    func validateExpressions(
        for node: FeatureNode,
        using parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateExpressions(for: node, using: parameters, tolerance: tolerance, execution: &execution)
    }

    func validateExpressions(
        for node: FeatureNode,
        using parameters: ParameterTable,
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        switch node.operation {
            case let .involuteGear(gear):
                _ = try gear.resolvedDimensions(using: &execution) { expression, execution in
                    try parameters.resolvedValue(for: expression, using: &execution)
                }
            case .spatialPath:
                break
            case let .sketch(sketch):
                try sketch.validateExpressions(using: parameters, execution: &execution)
            case .importedBRep:
                break
            case let .primitive(primitive):
                try validatePrimitiveExpressions(
                    primitive,
                    using: parameters,
                    tolerance: tolerance,
                    execution: &execution
                )
            case let .extrude(extrude):
                _ = try extrude.resolvedAxialRange(tolerance: tolerance, using: &execution) { expression, execution in
                    try parameters.resolvedValue(for: expression, using: &execution)
                }
            case let .revolve(revolve):
                let angle = try parameters.resolvedValue(for: revolve.angle, using: &execution)
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
                try sweep.options.validate(using: &execution)
                if let expression = sweep.options.approximationTolerance {
                    let allowance = try parameters.resolvedValue(for: expression, using: &execution)
                    guard allowance.kind == .length, allowance.value.isFinite, allowance.value > 0 else {
                        throw FeatureEvaluationError.invalidGraph("Sweep approximation tolerance must resolve to a finite positive length.")
                    }
                }
                let twistAngle = try parameters.resolvedValue(for: sweep.options.twistAngle, using: &execution)
                guard twistAngle.kind == .angle else {
                    throw UnitError.expectedQuantity(
                        operation: "sweep.options.twistAngle",
                        expected: .angle,
                        actual: twistAngle.kind
                    )
                }
                let endScale = try parameters.resolvedValue(for: sweep.options.endScale, using: &execution)
                if let law = sweep.options.twistLaw {
                    let angles = (try OriginalParameterQueryStorage.map(law, using: &execution, transform: { value, execution in try parameters.resolvedValue(for: value.angle, using: &execution) }))
                    guard (try OriginalParameterQueryStorage.allSatisfy(angles, using: &execution, predicate: { value, execution in value.kind == .angle && value.value.isFinite })),
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
                let distanceFraction = try parameters.resolvedValue(for: sweep.options.distanceFraction, using: &execution)
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
                try edgeCurve.validate(using: &execution)
            case let .squareSurface(square):
                try square.validate(using: &execution)
            case let .xnurbs(xnurbs):
                try xnurbs.validate(using: &execution)
            case let .curvePatch(patch):
                try patch.validate(using: &execution)
            case let .sheetBridge(bridge):
                try bridge.validate(using: &execution)
            case let .pipe(pipe):
                try pipe.validate(using: &execution)
                func resolved(_ expression: CADExpression, _ kind: QuantityKind, _ name: String) throws -> Double {
                    let value = try parameters.resolvedValue(for: expression, using: &execution)
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
                _ = try resolved(pipe.twist, .angle, "twist")
                let endScale = try resolved(pipe.endScale, .scalar, "endScale")
                let allowance = try resolved(pipe.approximationTolerance, .length, "approximationTolerance")
                // A wall grows outward of the section when positive and inward when negative; an
                // inward wall is thinner than the radius. A custom profile's wall is checked
                // against its section when it is offset. Start below 0 and end above 1 run the
                // path on along its end tangents.
                let diameterAdmitted = diameter.map { diameter in
                    diameter > tolerance.distance && (thickness.map { $0 > 0 || -2 * $0 < diameter } ?? true)
                } ?? true
                guard diameterAdmitted, thickness.map({ abs($0) > tolerance.distance }) ?? true,
                      start < end, start < 1, end > 0, endScale > tolerance.relative, allowance > 0 else {
                    throw FeatureEvaluationError.invalidGraph(
                        "A pipe needs a positive diameter, a nonzero wall (inward thinner than its radius), start < end with start < 1 < end allowed past the path's ends, a positive end scale and allowance."
                    )
                }
            case let .loft(loft):
                try loft.validate(using: &execution)
            case let .boolean(boolean):
                try boolean.validate(using: &execution)
            case let .polySpline(polySpline):
                try polySpline.validate(tolerance: tolerance, using: &execution)
            case let .constrainedSurface(surface):
                try surface.validate(tolerance: tolerance, using: &execution)
            case let .bSplineSurface(surface):
                try surface.validate(tolerance: tolerance, using: &execution)
            case let .patchSurface(patch):
                try patch.validate(tolerance: tolerance, using: &execution)
            case .surfaceFill:
                break
            case let .faceLoopOffset(faceLoopOffset):
                let distance = try parameters.resolvedValue(for: faceLoopOffset.distance, using: &execution)
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
                let distance = try parameters.resolvedValue(for: edgeOffset.distance, using: &execution)
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
                try faceKnife.validate(using: &execution)
            case let .faceDelete(faceDelete):
                try faceDelete.validate(using: &execution)
            case let .faceDraft(faceDraft):
                try faceDraft.validate(using: &execution)
            case let .faceOffset(offset):
                try offset.validate(using: &execution)
                let distance = try parameters.resolvedValue(for: offset.distance, using: &execution)
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
                    let angle = try parameters.resolvedValue(for: adjacentAngle, using: &execution)
                    guard angle.kind == .angle else {
                        throw UnitError.expectedQuantity(operation: "faceOffset.adjacentAngle", expected: .angle, actual: angle.kind)
                    }
                    guard angle.value.isFinite, abs(angle.value) < Double.pi / 2 else {
                        throw FeatureEvaluationError.invalidGraph("Push Face adjacent angle must lie strictly between -90 and 90 degrees.")
                    }
                }
            case let .faceMove(move):
                try move.validate(tolerance: tolerance, using: &execution)
                let distance = try parameters.resolvedValue(for: move.translation.distance, using: &execution)
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
                try move.validate(tolerance: tolerance, using: &execution)
                let distance = try parameters.resolvedValue(for: move.translation.distance, using: &execution)
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
                try move.validate(tolerance: tolerance, using: &execution)
                let distance = try parameters.resolvedValue(for: move.translation.distance, using: &execution)
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
                try transform.validate(tolerance: tolerance, using: &execution)
                let expected: QuantityKind
                switch transform.motion {
                case .translation: expected = .length
                case .rotation: expected = .angle
                case .scale: expected = .scalar
                }
                switch transform.motion {
                case .translation, .rotation:
                    try execution.retainStorage(count: 1, stride: MemoryLayout<CADExpression>.stride)
                case .scale: break
                }
                for expression in transform.motion.expressions {
                    try execution.consumeWork(1)
                    let value = try parameters.resolvedValue(for: expression, using: &execution)
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
                try pattern.validate(tolerance: tolerance, using: &execution)
                let spacing = try parameters.resolvedValue(for: pattern.spacing, using: &execution)
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
                try pattern.validate(tolerance: tolerance, using: &execution)
                let spacing = try parameters.resolvedValue(for: pattern.angularSpacing, using: &execution)
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
                try pattern.validate(tolerance: tolerance, using: &execution)
                let firstSpacing = try parameters.resolvedValue(for: pattern.firstSpacing, using: &execution)
                let secondSpacing = try parameters.resolvedValue(for: pattern.secondSpacing, using: &execution)
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
                try pattern.validate(tolerance: tolerance, using: &execution)
            case let .mirror(mirror):
                try mirror.validate(tolerance: tolerance, using: &execution)
            case let .joinBodies(join):
                try join.validate(using: &execution)
            case let .unjoinBody(unjoin):
                try unjoin.validate(using: &execution)
            case let .unjoinFaces(unjoin):
                try unjoin.validate(using: &execution)
            case let .reverseSheet(reverse):
                try reverse.validate(using: &execution)
            case let .isoparam(feature):
                try feature.validate(using: &execution)
            case let .imprintBody(feature):
                try feature.validate(using: &execution)
            case let .faceMatch(feature):
                try feature.validate(using: &execution)
            case let .removeFillets(feature):
                try feature.validate(using: &execution)
            case let .removeRedundantTopology(feature):
                try feature.validate(using: &execution)
            case let .sheetExtend(feature):
                try feature.validate(using: &execution)
            case let .faceRebuild(feature):
                try feature.validate(using: &execution)
            case let .faceUnwrap(feature):
                try feature.validate(using: &execution)
            case let .surfaceAlign(feature):
                try feature.validate(using: &execution)
            case let .untrimFace(feature):
                try feature.validate(using: &execution)
            case let .imprintCurves(feature):
                try feature.validate(using: &execution)
            case let .extract(extract):
                try extract.validate(using: &execution)
            case let .wrap(wrap):
                try wrap.validate(using: &execution)
                guard try parameters.resolvedValue(for: wrap.options.offsetN, using: &execution).kind == .length else {
                    throw FeatureEvaluationError.invalidGraph("Wrap N offset must be a length.")
                }
            case let .chamfer(chamfer):
                try chamfer.validate(using: &execution)
                let distance = try parameters.resolvedValue(for: chamfer.distance, using: &execution)
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
                try fillet.validate(using: &execution)
                let radius = try parameters.resolvedValue(for: fillet.radius, using: &execution)
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
                if let endRadius = fillet.endRadius {
                    let end = try parameters.resolvedValue(for: endRadius, using: &execution)
                    guard end.kind == .length else {
                        throw UnitError.expectedQuantity(operation: "fillet.endRadius", expected: .length, actual: end.kind)
                    }
                    guard end.value > 0.0 else {
                        throw FeatureEvaluationError.invalidDistance(end.value)
                    }
                }
            case let .g2Blend(blend):
                try blend.validate(using: &execution)
                let distance = try parameters.resolvedValue(for: blend.distance, using: &execution)
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
                try corner.validate(using: &execution)
                let radius = try parameters.resolvedValue(for: corner.radius, using: &execution)
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
                try shell.validate(using: &execution)
                let thickness = try parameters.resolvedValue(for: shell.thickness, using: &execution)
                guard thickness.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "shell.thickness",
                        expected: .length,
                        actual: thickness.kind
                    )
                }
                // Positive walls outward (the solid the cavity), negative inward, as Plasticity's sign.
                guard thickness.value != 0.0, thickness.value.isFinite else {
                    throw FeatureEvaluationError.invalidDistance(thickness.value)
                }
            case let .thicken(thicken):
                try thicken.validate(using: &execution)
                let front = try parameters.resolvedValue(for: thicken.front, using: &execution)
                let back = try parameters.resolvedValue(for: thicken.back, using: &execution)
                for (side, value) in [("thicken.front", front), ("thicken.back", back)] {
                    try execution.consumeWork(1)
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
                try bridgeCurve.validate(tolerance: tolerance, using: &execution)
            case let .bridgeSurface(bridgeSurface):
                try bridgeSurface.validate(tolerance: tolerance, using: &execution)
            case let .curveEdit(curveEdit):
                try curveEdit.validate(tolerance: tolerance, using: &execution)
            case let .curveOffset(curveOffset):
                let distance = try parameters.resolvedValue(for: curveOffset.distance, using: &execution)
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
                try projectCurve.validate(tolerance: tolerance, using: &execution)
            case let .curveTrim(curveTrim):
                try curveTrim.validate(tolerance: tolerance, using: &execution)
            case let .curveExtend(extensionRequest):
                try extensionRequest.validate(using: &execution)
                let distance = try parameters.resolvedValue(for: extensionRequest.distance, using: &execution)
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
                try match.validate(using: &execution)
            case let .surfaceOffset(offset):
                try offset.validate(using: &execution)
                let distance = try parameters.resolvedValue(for: offset.distance, using: &execution)
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
                try trim.validate(tolerance: tolerance, using: &execution)
            case let .surfaceExtend(extensionRequest):
                try extensionRequest.validate(tolerance: tolerance, using: &execution)
            case let .surfaceMatch(match):
                try match.validate(using: &execution)
        }
    }

    private func validatePrimitiveExpressions(
        _ feature: PrimitiveFeature,
        using parameters: ParameterTable,
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        try feature.validate(tolerance: tolerance, using: &execution)
        func positiveLength(_ expression: CADExpression, name: String) throws -> Double {
            let quantity = try parameters.resolvedValue(for: expression, using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateOperationContract(for: node, tolerance: tolerance, using: &execution)
    }

    func validateOperationContract(for node: FeatureNode, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard (try OriginalParameterQueryStorage.set(node.inputs, using: &execution)).count == node.inputs.count else {
            throw FeatureEvaluationError.invalidGraph("Feature inputs contain duplicate references.")
        }
        let outputRoles = (try OriginalParameterQueryStorage.map(node.outputs, using: &execution, transform: { value, execution in value.role }))
        guard (try OriginalParameterQueryStorage.set(outputRoles, using: &execution)).count == outputRoles.count else {
            throw FeatureEvaluationError.invalidGraph("Feature outputs contain duplicate roles.")
        }
        switch node.operation.kind {
        case .involuteGear:
            try validateInvoluteGearContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .spatialPath:
            try validateSpatialPathContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .sketch:
            try validateSketchContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .importedBRep:
            try validateImportedBRepContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .primitive:
            try validatePrimitiveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .extrude:
            try validateExtrudeContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .revolve:
            try validateRevolveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .sweep:
            try validateSweepContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .pipe:
            try validatePipeContract(node, outputRoles: outputRoles, execution: &execution)
        case .edgeCurve:
            try validateEdgeCurveContract(node, outputRoles: outputRoles, execution: &execution)
        case .sheetBridge:
            try validateSheetBridgeContract(node, outputRoles: outputRoles, execution: &execution)
        case .curvePatch:
            try validateCurvePatchContract(node, outputRoles: outputRoles, execution: &execution)
        case .squareSurface:
            try validateSquareSurfaceContract(node, outputRoles: outputRoles, execution: &execution)
        case .xnurbs:
            try validateXNurbsContract(node, outputRoles: outputRoles, execution: &execution)
        case .loft:
            try validateLoftContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .boolean:
            try validateBooleanContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .polySpline:
            try validatePolySplineContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .constrainedSurface:
            try validateConstrainedSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .bSplineSurface:
            try validateBSplineSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .patchSurface:
            try validatePatchSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .surfaceFill:
            try validateSurfaceFillContract(node, outputRoles: outputRoles, execution: &execution)
        case .faceLoopOffset:
            try validateFaceLoopOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .edgeOffset:
            try validateEdgeOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .faceKnife:
            try validateFaceKnifeContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .faceDelete:
            try validateFaceDeleteContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .faceDraft:
            try validateFaceDraftContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .faceOffset:
            try validateFaceOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .faceMove:
            try validateFaceMoveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .edgeMove:
            try validateEdgeMoveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .vertexMove:
            try validateVertexMoveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .topologyTransform:
            try validateTopologyTransformContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .linearPattern:
            try validateLinearPatternContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .radialPattern:
            try validateRadialPatternContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .gridPattern:
            try validateGridPatternContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveDrivenPattern:
            try validateCurveDrivenPatternContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .mirror:
            try validateMirrorContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .joinBodies:
            try validateJoinBodiesContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .unjoinBody:
            try validateUnjoinBodyContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .unjoinFaces:
            try validateUnjoinFacesContract(node, outputRoles: outputRoles, execution: &execution)
        case .reverseSheet:
            try validateReverseSheetContract(node, outputRoles: outputRoles, execution: &execution)
        case .isoparam, .imprintBody, .untrimFace, .imprintCurves:
            try validateImprintContract(node, outputRoles: outputRoles, execution: &execution)
        case .faceMatch:
            try validateFaceMatchContract(node, outputRoles: outputRoles, execution: &execution)
        case .removeFillets:
            try validateRemoveFilletsContract(node, outputRoles: outputRoles, execution: &execution)
        case .removeRedundantTopology:
            try validateRemoveRedundantTopologyContract(node, outputRoles: outputRoles, execution: &execution)
        case .sheetExtend:
            try validateSheetExtendContract(node, outputRoles: outputRoles, execution: &execution)
        case .faceRebuild:
            try validateFaceRebuildContract(node, outputRoles: outputRoles, execution: &execution)
        case .faceUnwrap:
            try validateFaceUnwrapContract(node, outputRoles: outputRoles, execution: &execution)
        case .surfaceAlign:
            try validateSurfaceAlignContract(node, outputRoles: outputRoles, execution: &execution)
        case .extract:
            try validateExtractContract(node, outputRoles: outputRoles, execution: &execution)
        case .wrap:
            try validateWrapContract(node, outputRoles: outputRoles, execution: &execution)
        case .chamfer:
            try validateChamferContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .fillet:
            try validateFilletContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .g2Blend:
            try validateG2BlendContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .setbackCorner:
            try validateSetbackCornerContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .shell:
            try validateShellContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .thicken:
            try validateThickenContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .bridgeCurve:
            try validateBridgeCurveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .bridgeSurface:
            try validateBridgeSurfaceContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveEdit:
            try validateCurveEditContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveOffset:
            try validateCurveOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .projectCurve:
            try validateProjectCurveContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveTrim:
            try validateCurveTrimContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveExtend:
            try validateCurveExtendContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .curveMatch:
            try validateCurveMatchContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .surfaceOffset:
            try validateSurfaceOffsetContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .surfaceTrim:
            try validateSurfaceTrimContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .surfaceExtend:
            try validateSurfaceExtendContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        case .surfaceMatch:
            try validateSurfaceMatchContract(node, outputRoles: outputRoles, tolerance: tolerance, execution: &execution)
        }
    }

    @inline(never)
    private func validateInvoluteGearContract(_ node: FeatureNode, outputRoles: [FeaturePort], tolerance: ModelingTolerance, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .involuteGear(gear) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a involuteGear operation.")
        }
        guard node.inputs.isEmpty, outputRoles == [.body] else {
            throw FeatureEvaluationError.invalidGraph("Gear source requires no feature inputs and one body output.")
        }
        try gear.validate(tolerance: tolerance, using: &execution)
    }

    @inline(never)
    private func validateSpatialPathContract(_ node: FeatureNode, outputRoles: [FeaturePort], tolerance: ModelingTolerance, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .spatialPath(path) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a spatialPath operation.")
        }
        guard node.inputs.isEmpty, outputRoles == [.curve] else {
            throw FeatureEvaluationError.invalidGraph("Spatial paths have no inputs and exactly one curve output.")
        }
        try path.validate(tolerance: tolerance, using: &execution)
    }

    @inline(never)
    private func validateEdgeCurveContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .edgeCurve(edgeCurve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an edgeCurve operation.")
        }
        try edgeCurve.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: edgeCurve.source, role: edgeCurve.bodyRole)], using: &execution),
              (try OriginalParameterQueryStorage.optionalMap(nodes[edgeCurve.source], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == edgeCurve.bodyRole }
            }) == true,
              outputRoles == [.curve] else {
            throw FeatureEvaluationError.invalidGraph("Edge curves consume their body and declare one curve output.")
        }
    }

    @inline(never)
    private func validateSheetBridgeContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .sheetBridge(bridge) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sheetBridge operation.")
        }
        try bridge.validate(using: &execution)
        let declaredInputs = try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
            try execution.consumeWork(2)
            return bridge.inputs
        }
        guard try node.validationInputsEqual(declaredInputs, using: &execution),
              try OriginalParameterQueryStorage.allSatisfy(declaredInputs, using: &execution, predicate: { input, execution in (try OriginalParameterQueryStorage.optionalMap(nodes[input.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .sheet }
            }) == true }),
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("A Bridge Surface consumes two sheets and declares one sheet output.")
        }
    }

    @inline(never)
    private func validateCurvePatchContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .curvePatch(patch) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curvePatch operation.")
        }
        try patch.validate(using: &execution)
        guard try node.validationInputsEqual(patch.validationInputs(using: &execution), using: &execution),
              try OriginalParameterQueryStorage.allSatisfy((try patch.validationInputs(using: &execution)), using: &execution, predicate: { input, execution in (try OriginalParameterQueryStorage.optionalMap(nodes[input.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .curve }
            }) == true }),
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("A curve patch consumes its curves and declares one sheet output.")
        }
    }

    @inline(never)
    private func validateSquareSurfaceContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .squareSurface(square) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a squareSurface operation.")
        }
        try square.validate(using: &execution)
        guard try node.validationInputsEqual(square.validationInputs(using: &execution), using: &execution),
              try OriginalParameterQueryStorage.allSatisfy((try square.validationInputs(using: &execution)), using: &execution, predicate: { input, execution in (try OriginalParameterQueryStorage.optionalMap(nodes[input.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == input.role }
            }) == true }),
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("A Square consumes its side curves and continuity bodies and declares one sheet output.")
        }
    }

    @inline(never)
    private func validateXNurbsContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .xnurbs(xnurbs) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an xnurbs operation.")
        }
        try xnurbs.validate(using: &execution)
        guard try node.validationInputsEqual(xnurbs.validationInputs(using: &execution), using: &execution),
              try OriginalParameterQueryStorage.allSatisfy((try xnurbs.validationInputs(using: &execution)), using: &execution, predicate: { input, execution in (try OriginalParameterQueryStorage.optionalMap(nodes[input.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == input.role }
            }) == true }),
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("An XNURBS consumes its boundary and guide curves and continuity bodies and declares one sheet output.")
        }
    }

    @inline(never)
    private func validateConstrainedSurfaceContract(_ node: FeatureNode, outputRoles: [FeaturePort], tolerance: ModelingTolerance, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .constrainedSurface(surface) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a constrainedSurface operation.")
        }
        try surface.validate(tolerance: tolerance, using: &execution)
        guard node.inputs.isEmpty, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Constrained Surface requires no inputs and one Sheet output.")
        }
    }

    @inline(never)
    private func validateSketchContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .sketch(sketch) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sketch operation.")
        }
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Sketch features must not declare inputs.")
        }
        let allowedSketchOutputs: Set<FeaturePort> = [.profile, .curve]
        guard outputRoles.isEmpty == false,
              (try OriginalParameterQueryStorage.set(outputRoles, using: &execution)).isSubset(of: allowedSketchOutputs) else {
            throw FeatureEvaluationError.invalidGraph("Sketch features must declare profile or curve outputs.")
        }
        try sketch.validate(tolerance: tolerance, using: &execution)
    }

    @inline(never)
    private func validatePrimitiveContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .primitive(primitive) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a primitive operation.")
        }
        try primitive.validate(tolerance: tolerance, using: &execution)
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .importedBRep(importedBRep) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an imported B-rep operation.")
        }
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Imported B-rep features must not declare inputs.")
        }
        try importedBRep.validate(tolerance: tolerance, using: &execution)
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .extrude(extrude) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a extrude operation.")
        }
        try extrude.validate(using: &execution)
        var expectedInputs: [FeatureInput] = []
        try OriginalParameterQueryStorage.append(FeatureInput(featureID: extrude.section.featureID, role: extrude.section.inputRole), to: &expectedInputs, using: &execution)
        for target in extrude.targets {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target.featureID, role: .target), to: &expectedInputs, using: &execution)
        }
        guard try node.validationInputsEqual(expectedInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Extrude features must consume the referenced section input.")
        }
        guard let source = nodes[extrude.section.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == extrude.section.inputRole }))) else {
            throw FeatureEvaluationError.invalidGraph("Extrude source must declare the section input role.")
        }
        for target in extrude.targets {
            try execution.consumeWork(1)
            guard (try OriginalParameterQueryStorage.optionalMap(nodes[target.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .body }
            }) == true else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .revolve(revolve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a revolve operation.")
        }
        try revolve.validate(tolerance: tolerance, using: &execution)
        var expectedInputs: [FeatureInput] = []
        try OriginalParameterQueryStorage.append(FeatureInput(featureID: revolve.section.featureID, role: revolve.section.inputRole), to: &expectedInputs, using: &execution)
        for target in revolve.targets {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target.featureID, role: .target), to: &expectedInputs, using: &execution)
        }
        guard try node.validationInputsEqual(expectedInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Revolve features must consume the referenced section and target inputs.")
        }
        guard let source = nodes[revolve.section.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == revolve.section.inputRole }))) else {
            throw FeatureEvaluationError.invalidGraph("Revolve source must declare the section input role.")
        }
        for target in revolve.targets {
            try execution.consumeWork(1)
            guard (try OriginalParameterQueryStorage.optionalMap(nodes[target.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .body }
            }) == true else {
                throw FeatureEvaluationError.invalidGraph("Revolve Boolean target must declare a solid body output.")
            }
        }
        guard outputRoles == [revolve.resultKind == .solid ? .body : .sheet] else {
            throw FeatureEvaluationError.invalidGraph("Revolve output must agree with its body kind.")
        }
    }

    @inline(never)
    private func validatePipeContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .pipe(pipe) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a pipe operation.")
        }
        try pipe.validate(using: &execution)
        guard try node.validationInputsEqual(pipe.validationInputs(using: &execution), using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Pipe features must consume their profile, path and target inputs.")
        }
        if let profile = pipe.profile {
            guard (try OriginalParameterQueryStorage.optionalMap(nodes[profile.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == profile.inputRole }
            }) == true else {
                throw FeatureEvaluationError.invalidGraph("Pipe profile source must declare a \(profile.inputRole.rawValue) output.")
            }
        }
        guard (try OriginalParameterQueryStorage.optionalMap(nodes[pipe.path.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .curve }
            }) == true else {
            throw FeatureEvaluationError.invalidGraph("Pipe path source must declare a curve output.")
        }
        for target in pipe.targets {
            try execution.consumeWork(1)
            guard (try OriginalParameterQueryStorage.optionalMap(nodes[target.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .body }
            }) == true else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .sweep(sweep) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sweep operation.")
        }
        try sweep.validate(using: &execution)
        var expectedInputs: [FeatureInput] = []
        for section in sweep.sections {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: section.featureID, role: section.inputRole), to: &expectedInputs, using: &execution)
        }
        try OriginalParameterQueryStorage.append(FeatureInput(featureID: sweep.path.featureID, role: .path), to: &expectedInputs, using: &execution)
        for guide in sweep.guides {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: guide.featureID, role: .guide), to: &expectedInputs, using: &execution)
        }
        for target in sweep.targets {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target.featureID, role: .target), to: &expectedInputs, using: &execution)
        }
        let sourceInputSet = try OriginalParameterQueryStorage.set(node.inputs, using: &execution)
        let expectedInputSet = try OriginalParameterQueryStorage.set(expectedInputs, using: &execution)
        guard sourceInputSet.count == expectedInputSet.count,
              try OriginalParameterQueryStorage.allSatisfy(sourceInputSet, using: &execution, predicate: { input, execution in expectedInputSet.contains(input) }),
              node.inputs.count == expectedInputs.count else {
            throw FeatureEvaluationError.invalidGraph("Sweep features must consume the declared section, path, guide, and target inputs.")
        }
        for section in sweep.sections {
            try execution.consumeWork(1)
            guard let source = nodes[section.featureID],
                  ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == section.inputRole }))) else {
                throw FeatureEvaluationError.invalidGraph("Sweep section source must declare a \(section.inputRole.rawValue) output.")
            }
        }
        guard let pathSource = nodes[sweep.path.featureID],
              ((try OriginalParameterQueryStorage.contains(pathSource.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
            throw FeatureEvaluationError.invalidGraph("Sweep path source must declare a curve output.")
        }
        for guide in sweep.guides {
            try execution.consumeWork(1)
            guard let guideSource = nodes[guide.featureID],
                  ((try OriginalParameterQueryStorage.contains(guideSource.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
                throw FeatureEvaluationError.invalidGraph("Sweep guide source must declare a curve output.")
            }
        }
        for target in sweep.targets {
            try execution.consumeWork(1)
            guard let targetSource = nodes[target.featureID],
                  ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .loft(loft) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a loft operation.")
        }
        try loft.validate(using: &execution)
        let expectedInputs = (try loft.validationInputs(using: &execution))
        let sourceInputSet = try OriginalParameterQueryStorage.set(node.inputs, using: &execution)
        let expectedInputSet = try OriginalParameterQueryStorage.set(expectedInputs, using: &execution)
        guard sourceInputSet.count == expectedInputSet.count,
              try OriginalParameterQueryStorage.allSatisfy(sourceInputSet, using: &execution, predicate: { input, execution in expectedInputSet.contains(input) }),
              node.inputs.count == expectedInputs.count else {
            throw FeatureEvaluationError.invalidGraph("Loft features must consume the declared section and guide inputs.")
        }
        for section in loft.sections {
            try execution.consumeWork(1)
            for input in (try section.validationInputs(using: &execution)) {
                try execution.consumeWork(1)
                guard let source = nodes[input.featureID], ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == input.role }))) else {
                    throw FeatureEvaluationError.invalidGraph("Loft section source must declare its requested output kind.")
                }
            }
        }
        for guide in loft.guides {
            try execution.consumeWork(1)
            guard let source = nodes[guide.featureID],
                  ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .boolean(boolean) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a boolean operation.")
        }
        try boolean.validate(using: &execution)
        var expectedInputs = try OriginalParameterQueryStorage.map(boolean.targets, using: &execution) { target, execution in
            FeatureInput(featureID: target.featureID, role: .target)
        }
        for tool in boolean.tools {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: tool.featureID, role: .body), to: &expectedInputs, using: &execution)
        }
        let sourceInputSet = try OriginalParameterQueryStorage.set(node.inputs, using: &execution)
        let expectedInputSet = try OriginalParameterQueryStorage.set(expectedInputs, using: &execution)
        guard sourceInputSet.count == expectedInputSet.count,
              try OriginalParameterQueryStorage.allSatisfy(sourceInputSet, using: &execution, predicate: { input, execution in expectedInputSet.contains(input) }),
              node.inputs.count == expectedInputs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean features must consume declared target and tool body inputs.")
        }
        let targetPorts = (try OriginalParameterQueryStorage.map(boolean.targets, using: &execution, transform: { target, execution in
            guard let port = (try nodes[target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
                throw FeatureEvaluationError.invalidGraph("Boolean target source must declare a body or sheet output.")
            }
            return port }))
        for tool in boolean.tools {
            try execution.consumeWork(1)
            guard (try nodes[tool.featureID]?.validationBodyOrSheetOutput(using: &execution)) != nil else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .polySpline(polySpline) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a polySpline operation.")
        }
        try polySpline.validate(tolerance: tolerance, using: &execution)
        guard node.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("PolySpline features must not declare inputs in the inline mesh subset.")
        }
        // A closed mesh closes into a solid, any other into a sheet.
        guard outputRoles == [(try polySpline.sourceMesh.validationIsClosedSurface(using: &execution)) ? .body : .sheet] else {
            throw FeatureEvaluationError.invalidGraph("PolySpline features declare one body output for a closed mesh and one sheet output otherwise.")
        }
    }

    @inline(never)
    private func validateBSplineSurfaceContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .bSplineSurface(surface) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bSplineSurface operation.")
        }
        try surface.validate(tolerance: tolerance, using: &execution)
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .patchSurface(patch) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a patchSurface operation.")
        }
        try patch.validate(tolerance: tolerance, using: &execution)
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
        outputRoles: [FeaturePort],
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .surfaceFill(fill) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceFill operation.")
        }
        try fill.validate(using: &execution)
        guard try node.validationInputsEqual(fill.validationInputs(using: &execution), using: &execution),
              let source = nodes[fill.targetFeatureID],
              (try OriginalParameterQueryStorage.filter(source.outputs, using: &execution, predicate: { value, execution in value.role == .body || value.role == .sheet })).count == 1,
              (try OriginalParameterQueryStorage.optionalMap(fill.insertedSheet, using: &execution) { id, execution in
                  guard let node = nodes[id] else { return false }
                  return try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .sheet }
              }) ?? true,
              outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Surface fill requires one body target input and one sheet output.")
        }
    }

    @inline(never)
    private func validateFaceLoopOffsetContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceLoopOffset(faceLoopOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceLoopOffset operation.")
        }
        try faceLoopOffset.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: faceLoopOffset.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face loop offset features must consume the referenced target body input.")
        }
        guard let targetPort = (try nodes[faceLoopOffset.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .edgeOffset(edgeOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a edgeOffset operation.")
        }
        try edgeOffset.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: edgeOffset.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Edge offset features must consume the referenced target body input.")
        }
        guard let targetPort = (try nodes[edgeOffset.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceKnife(faceKnife) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceKnife operation.")
        }
        try faceKnife.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: faceKnife.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face Knife features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[faceKnife.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceDelete(faceDelete) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceDelete operation.")
        }
        try faceDelete.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: faceDelete.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face Delete features must consume the referenced target body input.")
        }
        // A solid heals over its deleted faces; a sheet, or a solid that does not heal, loses them.
        guard let targetSource = nodes[faceDelete.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body || (faceDelete.heals == false && value.role == .sheet) }))) else {
            throw FeatureEvaluationError.invalidGraph("Face Delete target source must declare a body output, or a sheet output when it does not heal.")
        }
        guard outputRoles == [faceDelete.outputRole] else {
            throw FeatureEvaluationError.invalidGraph("Face Delete features must declare one sheet output, or one body output when they heal.")
        }
    }

    @inline(never)
    private func validateFaceDraftContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceDraft(faceDraft) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceDraft operation.")
        }
        try faceDraft.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: faceDraft.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face Draft features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[faceDraft.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceOffset(offset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceOffset operation.")
        }
        try offset.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: offset.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face offset features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[offset.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Face offset target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .faceMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceMove operation.")
        }
        try move.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: move.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Face move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Face move target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .edgeMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a edgeMove operation.")
        }
        try move.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: move.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Edge move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Edge move target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .vertexMove(move) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a vertexMove operation.")
        }
        try move.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: move.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Vertex move features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[move.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Vertex move target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .topologyTransform(transform) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a topologyTransform operation.")
        }
        try transform.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: transform.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Topology transform features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[transform.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Topology transform target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .linearPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a linearPattern operation.")
        }
        try pattern.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: pattern.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Linear pattern features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[pattern.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .radialPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a radialPattern operation.")
        }
        try pattern.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: pattern.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Radial pattern features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[pattern.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .gridPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a gridPattern operation.")
        }
        try pattern.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: pattern.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Grid pattern features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[pattern.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveDrivenPattern(pattern) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveDrivenPattern operation.")
        }
        try pattern.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([
            FeatureInput(featureID: pattern.target.featureID, role: .target),
            FeatureInput(featureID: pattern.path.featureID, role: .path),
        ], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve-driven pattern features must consume target body and path curve inputs.")
        }
        guard let targetSource = nodes[pattern.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
            throw FeatureEvaluationError.invalidGraph("Curve-driven pattern target source must declare a body output.")
        }
        guard let pathSource = nodes[pattern.path.featureID],
              ((try OriginalParameterQueryStorage.contains(pathSource.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .mirror(mirror) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a mirror operation.")
        }
        try mirror.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: mirror.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Mirror features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[mirror.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Mirror target source must declare a body or sheet output.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .joinBodies(join) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a joinBodies operation.")
        }
        try join.validate(using: &execution)
        let expectedInputs = (try OriginalParameterQueryStorage.map(join.targets, using: &execution, transform: { target, execution in
            FeatureInput(featureID: target.featureID, role: .target) }))
        guard try node.validationInputsEqual(expectedInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Join bodies features must consume the referenced target body inputs.")
        }
        for target in join.targets {
            try execution.consumeWork(1)
            guard let targetSource = nodes[target.featureID],
                  ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == join.mode.targetPort }))) else {
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
    private func validateWrapContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .wrap(wrap) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a wrap operation.")
        }
        try wrap.validate(using: &execution)
        guard try node.validationInputsEqual(wrap.validationSourceInputs(using: &execution), using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Wrap must consume its target and the owners of its reference and target faces.")
        }
        guard let sourcePort = (try nodes[wrap.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
            throw FeatureEvaluationError.invalidGraph("Wrap target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [try wrap.resultPort(sourcePort: sourcePort)] else {
            throw FeatureEvaluationError.invalidGraph("Wrap features must declare their target's output.")
        }
    }

    private func validateExtractContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .extract(extract) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an extract operation.")
        }
        try extract.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: extract.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Extract features must consume the referenced target input.")
        }
        guard let sourcePort = (try nodes[extract.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
            throw FeatureEvaluationError.invalidGraph("Extract target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [try extract.resultPort(sourcePort: sourcePort)] else {
            throw FeatureEvaluationError.invalidGraph("Extract features must declare the one output their selection gives.")
        }
    }

    private func validateUnjoinFacesContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .unjoinFaces(unjoin) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an unjoinFaces operation.")
        }
        try unjoin.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: unjoin.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces features must consume the referenced target input.")
        }
        guard (try nodes[unjoin.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) != nil else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces target source must declare exactly one body or sheet output.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin faces features must declare one sheet output.")
        }
    }

    /// Align Surface consumes its sheet, reads the reference's body, and publishes a sheet.
    private func validateSurfaceAlignContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .surfaceAlign(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceAlign operation.")
        }
        try feature.validate(using: &execution)
        let declaredInputs = try OriginalParameterQueryStorage.values(count: 2, using: &execution) { execution in
            try execution.consumeWork(2)
            return feature.inputs
        }
        guard try node.validationInputsEqual(declaredInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Align Surface features must consume exactly their referenced inputs.")
        }
        guard (try OriginalParameterQueryStorage.optionalMap(nodes[feature.target.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .sheet }
            }) == true,
              (try nodes[feature.reference.featureID]?.validationBodyOrSheetOutput(using: &execution)) != nil, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Align Surface takes a sheet and publishes one.")
        }
    }

    /// Rebuild Face reshapes its target's faces and publishes its target's kind of body.
    private func validateFaceRebuildContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .faceRebuild(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceRebuild operation.")
        }
        try feature.validate(using: &execution)
        let declaredInputs = try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            try execution.consumeWork(1)
            return feature.inputs
        }
        guard try node.validationInputsEqual(declaredInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face features must consume exactly their target.")
        }
        guard let targetPort = (try nodes[feature.target.featureID]?.validationBodyOrSheetOutput(using: &execution)), outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Rebuild Face publishes its target's kind of body.")
        }
    }

    /// Unwrap Face reads a body and publishes the flattened face as a sheet.
    private func validateFaceUnwrapContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .faceUnwrap(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceUnwrap operation.")
        }
        try feature.validate(using: &execution)
        let declaredInputs = try OriginalParameterQueryStorage.values(count: 1, using: &execution) { execution in
            try execution.consumeWork(1)
            return feature.inputs
        }
        guard try node.validationInputsEqual(declaredInputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Unwrap Face features must consume exactly their target.")
        }
        guard (try nodes[feature.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) != nil, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Unwrap Face reads a body or sheet and publishes a sheet.")
        }
    }

    /// Extend Sheet reads its sheet, consuming it when the extensions join it, and publishes a sheet.
    private func validateSheetExtendContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .sheetExtend(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a sheetExtend operation.")
        }
        try feature.validate(using: &execution)
        guard try node.validationInputsEqual(feature.validationInputs(using: &execution), using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Extend Sheet features must consume exactly their referenced inputs.")
        }
        guard (try OriginalParameterQueryStorage.optionalMap(nodes[feature.target.featureID], using: &execution) { node, execution in
                try OriginalParameterQueryStorage.contains(node.outputs, using: &execution) { value, execution in value.role == .sheet }
            }) == true, outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Extend Sheet takes a sheet and publishes one.")
        }
    }

    /// Delete Redundant Topology keeps its target's kind of body in its place.
    private func validateRemoveRedundantTopologyContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .removeRedundantTopology(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a removeRedundantTopology operation.")
        }
        try feature.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: feature.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Delete Redundant Topology features must consume exactly their target.")
        }
        guard let targetPort = (try nodes[feature.target.featureID]?.validationBodyOrSheetOutput(using: &execution)), outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Delete Redundant Topology publishes its target's kind of body.")
        }
    }

    /// Remove Fillets reshapes its solid target in its place.
    private func validateRemoveFilletsContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .removeFillets(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a removeFillets operation.")
        }
        try feature.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: feature.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Remove Fillets features must consume exactly their target.")
        }
        guard let targetPort = (try nodes[feature.target.featureID]?.validationBodyOrSheetOutput(using: &execution)), outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Remove Fillets takes a solid or a sheet and publishes the same kind of body.")
        }
    }

    /// Match Face reshapes its target and publishes it as the same kind of body, reading the
    /// reference face's body as well when that is another.
    private func validateFaceMatchContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .faceMatch(feature) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a faceMatch operation.")
        }
        try feature.validate(using: &execution)
        guard try node.validationInputsEqual(feature.validationInputs(using: &execution), using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Match Face features must consume exactly their referenced inputs.")
        }
        guard let targetPort = (try nodes[feature.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) else {
            throw FeatureEvaluationError.invalidGraph("Match Face target must declare one body or sheet output.")
        }
        guard (try nodes[feature.source.featureID]?.validationBodyOrSheetOutput(using: &execution)) != nil else {
            throw FeatureEvaluationError.invalidGraph("Match Face reference body must declare one body or sheet output.")
        }
        guard outputRoles == [targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Match Face features must publish their target's kind of body.")
        }
    }

    /// Isoparam and Imprint split their target and publish it as the same kind of body; Imprint
    /// reads its tool as well; Untrim publishes a sheet beside its target.
    private func validateImprintContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let target: FeatureID
        var inputs: [FeatureInput]
        var output: FeaturePort?
        switch node.operation {
        case let .isoparam(feature):
            try feature.validate(using: &execution)
            target = feature.target.featureID
            inputs = []
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target, role: .target), to: &inputs, using: &execution)
        case let .imprintBody(feature):
            try feature.validate(using: &execution)
            target = feature.target.featureID
            inputs = []
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target, role: .target), to: &inputs, using: &execution)
            for tool in feature.tools {
                try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(FeatureInput(featureID: tool.body.featureID, role: .body), to: &inputs, using: &execution)
            }
            for tool in feature.tools {
                try execution.consumeWork(1)
                if try nodes[tool.body.featureID]?.validationBodyOrSheetOutput(using: &execution) != nil { continue }
                throw FeatureEvaluationError.invalidGraph("Imprint's tool must declare one body or sheet output.")
            }
        case let .untrimFace(feature):
            try feature.validate(using: &execution)
            target = feature.target.featureID
            inputs = []
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target, role: .target), to: &inputs, using: &execution)
            output = .sheet
        case let .imprintCurves(feature):
            try feature.validate(using: &execution)
            target = feature.target.featureID
            inputs = []
            try OriginalParameterQueryStorage.append(FeatureInput(featureID: target, role: .target), to: &inputs, using: &execution)
            let curveInputs = try feature.validationCurveInputs(using: &execution)
            try OriginalParameterQueryStorage.append(contentsOf: curveInputs, to: &inputs, using: &execution)
        default:
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an imprint operation.")
        }
        guard try node.validationInputsEqual(inputs, using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Imprint features must consume exactly their referenced inputs.")
        }
        guard let targetPort = (try nodes[target]?.validationBodyOrSheetOutput(using: &execution)) else {
            throw FeatureEvaluationError.invalidGraph("An imprint's target must declare one body or sheet output.")
        }
        guard outputRoles == [output ?? targetPort] else {
            throw FeatureEvaluationError.invalidGraph("Imprint features must declare the one output their operation gives.")
        }
    }

    private func validateReverseSheetContract(_ node: FeatureNode, outputRoles: [FeaturePort], execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard case let .reverseSheet(reverse) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a reverseSheet operation.")
        }
        try reverse.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: reverse.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Reverse sheet features must consume the referenced target input.")
        }
        guard (try nodes[reverse.target.featureID]?.validationBodyOrSheetOutput(using: &execution)) == .sheet else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .unjoinBody(unjoin) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected an unjoinBody operation.")
        }
        try unjoin.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: unjoin.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Unjoin body features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[unjoin.target.featureID] else {
            throw FeatureEvaluationError.invalidGraph("Unjoin body target source is missing.")
        }
        let mappedRoles = (try OriginalParameterQueryStorage.map(targetSource.outputs, using: &execution, transform: { value, execution in value.role }))
        let targetRoles = try OriginalParameterQueryStorage.filter(mappedRoles, using: &execution) { value, execution in value == .body || value == .sheet }
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .chamfer(chamfer) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a chamfer operation.")
        }
        try chamfer.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: chamfer.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Chamfer features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[chamfer.target.featureID],
              let port = try OriginalParameterQueryStorage.first([FeaturePort.body, .sheet], using: &execution, predicate: { port, execution in (try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == port })) }) else {
            throw FeatureEvaluationError.invalidGraph("Chamfer target source must declare a body or sheet output.")
        }
        guard outputRoles == [port] else {
            throw FeatureEvaluationError.invalidGraph("A chamfer declares the output its target does: a body, or a sheet.")
        }
    }

    @inline(never)
    private func validateFilletContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .fillet(fillet) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a fillet operation.")
        }
        try fillet.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: fillet.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Fillet features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[fillet.target.featureID],
              let port = try OriginalParameterQueryStorage.first([FeaturePort.body, .sheet], using: &execution, predicate: { port, execution in (try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == port })) }) else {
            throw FeatureEvaluationError.invalidGraph("Fillet target source must declare a body or sheet output.")
        }
        guard outputRoles == [port] else {
            throw FeatureEvaluationError.invalidGraph("A fillet declares the output its target does: a body, or a sheet.")
        }
    }

    @inline(never)
    private func validateG2BlendContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .g2Blend(blend) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a g2Blend operation.")
        }
        try blend.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: blend.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("G2 blend features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[blend.target.featureID],
              let port = try OriginalParameterQueryStorage.first([FeaturePort.body, .sheet], using: &execution, predicate: { port, execution in (try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == port })) }) else {
            throw FeatureEvaluationError.invalidGraph("G2 blend target source must declare a body or sheet output.")
        }
        guard outputRoles == [port] else {
            throw FeatureEvaluationError.invalidGraph("A G2 blend declares the output its target does: a body, or a sheet.")
        }
    }

    @inline(never)
    private func validateSetbackCornerContract(
        _ node: FeatureNode,
        outputRoles: [FeaturePort],
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .setbackCorner(corner) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a setbackCorner operation.")
        }
        try corner.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: corner.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Setback corner features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[corner.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .shell(shell) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a shell operation.")
        }
        try shell.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: shell.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Shell features must consume the referenced target body input.")
        }
        guard let targetSource = nodes[shell.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .body }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .thicken(thicken) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a thicken operation.")
        }
        try thicken.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: thicken.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Thicken features must consume the referenced target sheet input.")
        }
        guard let targetSource = nodes[thicken.target.featureID],
              ((try OriginalParameterQueryStorage.contains(targetSource.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .bridgeCurve(bridgeCurve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bridgeCurve operation.")
        }
        try bridgeCurve.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([
            FeatureInput(featureID: bridgeCurve.start.curve.featureID, role: .curve),
            FeatureInput(featureID: bridgeCurve.end.curve.featureID, role: .target),
        ], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge curve features must consume their start and end curve references."
            )
        }
        guard let startSource = nodes[bridgeCurve.start.curve.featureID],
              ((try OriginalParameterQueryStorage.contains(startSource.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge curve start source must declare a curve output."
            )
        }
        guard let endSource = nodes[bridgeCurve.end.curve.featureID],
              ((try OriginalParameterQueryStorage.contains(endSource.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .bridgeSurface(bridgeSurface) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a bridgeSurface operation.")
        }
        try bridgeSurface.validate(tolerance: tolerance, using: &execution)
        guard try node.validationInputsEqual(bridgeSurface.validationSourceInputs(using: &execution), using: &execution) else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface must consume every source feature owning its boundary edges."
            )
        }
        for input in (try bridgeSurface.validationSourceInputs(using: &execution)) {
            try execution.consumeWork(1)
            guard let source = nodes[input.featureID],
                  (try OriginalParameterQueryStorage.filter(source.outputs, using: &execution, predicate: { value, execution in value.role == .body || value.role == .sheet })).count == 1 else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveEdit(curveEdit) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveEdit operation.")
        }
        try curveEdit.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: curveEdit.source.featureID, role: .curve)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve edit features must consume the referenced curve input.")
        }
        guard let source = nodes[curveEdit.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveOffset(curveOffset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveOffset operation.")
        }
        try curveOffset.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: curveOffset.source.featureID, role: .curve)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve offset features must consume the referenced curve input.")
        }
        guard let source = nodes[curveOffset.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .projectCurve(projectCurve) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a projectCurve operation.")
        }
        try projectCurve.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: projectCurve.source.featureID, role: .curve)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve projection features must consume the referenced curve input.")
        }
        guard let source = nodes[projectCurve.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveTrim(curveTrim) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveTrim operation.")
        }
        try curveTrim.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: curveTrim.source.featureID, role: .curve)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve trim features must consume the referenced curve input.")
        }
        guard let source = nodes[curveTrim.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveExtend(extensionRequest) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveExtend operation.")
        }
        try extensionRequest.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: extensionRequest.source.featureID, role: .curve)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve extend features must consume the referenced curve input.")
        }
        guard let source = nodes[extensionRequest.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .curveMatch(match) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a curveMatch operation.")
        }
        try match.validate(using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([
            FeatureInput(featureID: match.source.featureID, role: .curve),
            FeatureInput(featureID: match.target.featureID, role: .target),
        ], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Curve match features must consume source and target curve inputs.")
        }
        guard let source = nodes[match.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))),
              let target = nodes[match.target.featureID],
              ((try OriginalParameterQueryStorage.contains(target.outputs, using: &execution, predicate: { value, execution in value.role == .curve }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .surfaceOffset(offset) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceOffset operation.")
        }
        try offset.validate(using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: offset.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Surface offset features must consume the referenced sheet input.")
        }
        guard let source = nodes[offset.target.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .surfaceTrim(trim) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceTrim operation.")
        }
        try trim.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: trim.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Surface trim features must consume the referenced sheet input.")
        }
        guard let source = nodes[trim.target.featureID], ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .surfaceExtend(extensionRequest) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceExtend operation.")
        }
        try extensionRequest.validate(tolerance: tolerance, using: &execution)
        try execution.retainStorage(count: 1, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([FeatureInput(featureID: extensionRequest.target.featureID, role: .target)], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Surface extend features must consume the referenced sheet input.")
        }
        guard let source = nodes[extensionRequest.target.featureID], ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))) else {
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
        tolerance: ModelingTolerance,
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        guard case let .surfaceMatch(match) = node.operation else {
            throw FeatureEvaluationError.invalidGraph("Operation contract dispatch expected a surfaceMatch operation.")
        }
        try match.validate(using: &execution)
        try execution.retainStorage(count: 2, stride: MemoryLayout<FeatureInput>.stride)
        guard try node.validationInputsEqual([
            FeatureInput(featureID: match.source.featureID, role: .sheet),
            FeatureInput(featureID: match.target.featureID, role: .target),
        ], using: &execution) else {
            throw FeatureEvaluationError.invalidGraph("Surface match features must consume source and target sheet inputs.")
        }
        guard let source = nodes[match.source.featureID],
              ((try OriginalParameterQueryStorage.contains(source.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))),
              let target = nodes[match.target.featureID],
              ((try OriginalParameterQueryStorage.contains(target.outputs, using: &execution, predicate: { value, execution in value.role == .sheet }))) else {
            throw FeatureEvaluationError.invalidGraph("Surface match inputs must declare sheet outputs.")
        }
        guard outputRoles == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Surface match features must declare one sheet output.")
        }
    }

    private func validateAcyclicDependencies(execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var adjacency: [FeatureID: [FeatureID]] = [:]
        for dependency in dependencies {
            try execution.consumeWork(1)
            var targets = adjacency[dependency.source, default: []]
            if !targets.isEmpty {
                try execution.retainStorage(count: targets.count, stride: MemoryLayout<FeatureID>.stride)
            }
            (try OriginalParameterQueryStorage.append(dependency.target, to: &targets, using: &execution))
            (try OriginalParameterQueryStorage.set(targets, for: dependency.source, in: &adjacency, using: &execution))
        }
        var states: [FeatureID: VisitState] = [:]
        var stack: [FeatureID] = []
        var orderedIDs = try OriginalParameterQueryStorage.materialize(nodes.keys, using: &execution)
        try OriginalParameterQueryStorage.sort(&orderedIDs, using: &execution, comparing: { first, second, execution in
            // Canonical portable identities contain exactly 36 UTF-8 code units.
            try execution.retainStorage(count: 72, stride: MemoryLayout<UInt8>.stride)
            return first.description < second.description
        })
        for featureID in orderedIDs {
            try execution.consumeWork(1)
            try visit(featureID, adjacency: adjacency, states: &states, stack: &stack, execution: &execution)
        }
    }

    private func visit(
        _ featureID: FeatureID,
        adjacency: [FeatureID: [FeatureID]],
        states: inout [FeatureID: VisitState],
        stack: inout [FeatureID],
        execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        if states[featureID] == .visited {
            return
        }
        if states[featureID] == .visiting {
            let cycleStart = (try OriginalParameterQueryStorage.firstIndex(stack, using: &execution,
                predicate: { id, execution in id == featureID })) ?? stack.startIndex
            var cycleIDs = (try OriginalParameterQueryStorage.materialize(stack[cycleStart...], using: &execution))
            (try OriginalParameterQueryStorage.append(featureID, to: &cycleIDs, using: &execution))
            let descriptions = try OriginalParameterQueryStorage.map(cycleIDs, using: &execution) { id, execution in
                try execution.retainStorage(count: 36, stride: MemoryLayout<UInt8>.stride)
                let description = id.description
                return description
            }
            var cycle = ""
            for description in descriptions {
                try execution.consumeWork(1)
                if !cycle.isEmpty {
                    try execution.retainStorage(count: 4, stride: MemoryLayout<UInt8>.stride)
                    cycle += " -> "
                }
                try execution.retainStorage(count: description.utf8.count, stride: MemoryLayout<UInt8>.stride)
                cycle += description
            }
            throw FeatureEvaluationError.invalidGraph("Dependency cycle detected: \(cycle).")
        }

        try execution.admitSourceDepth(stack.count + 1)
        (try OriginalParameterQueryStorage.set(.visiting, for: featureID, in: &states, using: &execution))
        (try OriginalParameterQueryStorage.append(featureID, to: &stack, using: &execution))
        var orderedTargets = try OriginalParameterQueryStorage.materialize(adjacency[featureID, default: []], using: &execution)
        try OriginalParameterQueryStorage.sort(&orderedTargets, using: &execution, comparing: { first, second, execution in
            try execution.retainStorage(count: 72, stride: MemoryLayout<UInt8>.stride)
            return first.description < second.description
        })
        for targetID in orderedTargets {
            try execution.consumeWork(1)
            try visit(targetID, adjacency: adjacency, states: &states, stack: &stack, execution: &execution)
        }
        stack.removeLast()
        (try OriginalParameterQueryStorage.set(.visited, for: featureID, in: &states, using: &execution))
    }

    private func validateOrderRespectsDependencies(execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var positions: [FeatureID: Int] = [:]
        try execution.retainStorage(count: order.count, stride: MemoryLayout<(FeatureID, Int)>.stride)
        positions.reserveCapacity(order.count)
        for (index, featureID) in order.enumerated() {
            try execution.consumeWork(1)
            (try OriginalParameterQueryStorage.set(index, for: featureID, in: &positions, using: &execution))
        }
        for dependency in dependencies {
            try execution.consumeWork(1)
            guard let sourceIndex = positions[dependency.source],
                  let targetIndex = positions[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency references an unordered feature.")
            }
            guard sourceIndex < targetIndex else {
                throw FeatureEvaluationError.invalidGraph("Feature order violates dependency direction.")
            }
        }
        for (featureID, node) in nodes {
            try execution.consumeWork(1)
            guard let targetIndex = positions[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature node is unordered.")
            }
            for input in node.inputs {
                try execution.consumeWork(1)
                guard let sourceIndex = positions[input.featureID] else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references an unordered feature.")
                }
                guard sourceIndex < targetIndex else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must appear before the consuming feature.")
                }
            }
        }
    }

    private func validateInputsAreRepresentedByDependencies(execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let dependencySet = (try OriginalParameterQueryStorage.set(dependencies, using: &execution))
        for (featureID, node) in nodes {
            try execution.consumeWork(1)
            for input in node.inputs {
                try execution.consumeWork(1)
                let requiredDependency = DependencyEdge(source: input.featureID, target: featureID)
                guard dependencySet.contains(requiredDependency) else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must be represented by a dependency edge.")
                }
            }
        }
    }

    private func validateDependenciesAreRepresentedByInputs(execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for dependency in dependencies {
            try execution.consumeWork(1)
            guard let target = nodes[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
            guard ((try OriginalParameterQueryStorage.contains(target.inputs, using: &execution, predicate: { value, execution in value.featureID == dependency.source }))) else {
                throw FeatureEvaluationError.invalidGraph("Dependency edge must be represented by a feature input.")
            }
        }
    }

    private func validateActiveFeaturesDoNotDependOnSuppressedSources(execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var suppressedFeatureIDs = Set<FeatureID>()
        for (featureID, node) in nodes {
            try execution.consumeWork(1)
            if !node.isSuppressed { continue }
            (try OriginalParameterQueryStorage.insert(featureID, in: &suppressedFeatureIDs, using: &execution))
        }
        guard suppressedFeatureIDs.isEmpty == false else {
            return
        }

        for (_, node) in nodes {
            try execution.consumeWork(1)
            if node.isSuppressed { continue }
            for input in node.inputs {
                try execution.consumeWork(1)
                guard suppressedFeatureIDs.contains(input.featureID) == false else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Active feature input references a suppressed feature."
                    )
                }
            }
        }
        for dependency in dependencies {
            try execution.consumeWork(1)
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

public struct DependencyEdge: Sendable, Hashable {
    public var source: FeatureID
    public var target: FeatureID

    public init(source: FeatureID, target: FeatureID) {
        self.source = source
        self.target = target
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case source
        case target
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .target], in: decoder)
        source = try container.decode(FeatureID.self, forKey: .source)
        target = try container.decode(FeatureID.self, forKey: .target)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(target, forKey: .target)
    }
#endif
}

#if !hasFeature(Embedded)
extension DesignGraph: Codable {}
extension DependencyEdge: Codable {}
#endif
