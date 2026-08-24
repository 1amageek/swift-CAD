import CADCore
import CADIR
import CADTopology

package struct ExactPatternBodyUnionReducer: Sendable {
    private struct Operand: Sendable {
        let bodyID: BodyID
        let brep: BRepModel
        let subshapes: [SubshapeID: TopologyReference]
        let lineage: [SubshapeID: TopologyLineage]

        init(
            bodyID: BodyID,
            brep: BRepModel,
            subshapes: [SubshapeID: TopologyReference],
            lineage: [SubshapeID: TopologyLineage]
        ) {
            self.bodyID = bodyID
            self.brep = brep
            self.subshapes = subshapes
            self.lineage = lineage
        }

        init(_ result: BRepSewingResult) {
            self.init(
                bodyID: result.bodyID,
                brep: result.brep,
                subshapes: result.subshapes,
                lineage: result.lineage
            )
        }
    }

    private let applicator: any BooleanOperationApplying
    private let separationValidator: any BodyJoinValidating

    package init(
        applicator: any BooleanOperationApplying,
        separationValidator: any BodyJoinValidating
    ) {
        self.applicator = applicator
        self.separationValidator = separationValidator
    }

    package func reduce(
        instances: [BRepSewingResult],
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        guard instances.count >= 2 else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact pattern union requires at least two instance bodies."
            )
        }
        let operands = instances.map(Operand.init)
        var ancestry = try mergedLineage(operands.map(\.lineage))
        let combinedModel = try BRepModelCombiner().combined(operands.map(\.brep))
        let interactions = try separationValidator.materialInteractions(
            bodyIDs: operands.map(\.bodyID),
            in: combinedModel,
            tolerance: tolerance
        )
        let groups = try interactionGroups(
            operands: operands,
            interactions: interactions
        )
        let reduced = try reduceInteractionGroups(
            groups,
            finalFeatureID: featureID,
            ancestry: &ancestry,
            tolerance: tolerance
        )
        let lineage = try collapsedLineage(
            reduced.lineage,
            through: ancestry,
            featureID: featureID,
            tolerance: tolerance
        )
        return EvaluationResult(
            brep: reduced.brep,
            subshapes: reduced.subshapes,
            lineage: lineage
        )
    }

    private func disjointAggregate(
        operands: [Operand],
        combinedModel: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Operand {
        var resultModel = combinedModel
        var components: [SolidShellComponent] = []
        for operand in operands {
            guard let body = resultModel.bodies.removeValue(forKey: operand.bodyID),
                  case let .solid(bodyComponents) = body.topology else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Exact pattern disjoint aggregation requires solid instance bodies."
                )
            }
            components.append(contentsOf: bodyComponents)
        }
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        let bodyID = topologyIDs.nextBodyID()
        resultModel.bodies[bodyID] = Body(
            id: bodyID,
            solidComponents: components
        )
        try resultModel.validate(level: .volumetric, tolerance: tolerance)

        let bodySubshapeID = SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        var subshapes: [SubshapeID: TopologyReference] = [
            bodySubshapeID: .body(bodyID),
        ]
        var temporaryLineage: [SubshapeID: TopologyLineage] = [
            bodySubshapeID: TopologyLineage(
                output: bodySubshapeID,
                parents: operands.flatMap { operand in
                    operand.subshapes.compactMap { subshapeID, reference in
                        if case .body = reference { return subshapeID }
                        return nil
                    }
                },
                relation: .merged
            ),
        ]
        var nextOrdinalByRole: [String: Int] = [:]
        for operand in operands {
            for (sourceID, reference) in operand.subshapes.sorted(by: { $0.key < $1.key }) {
                if case .body = reference { continue }
                let ordinal = nextOrdinalByRole[sourceID.role, default: 0]
                nextOrdinalByRole[sourceID.role] = ordinal + 1
                let output = SubshapeID(
                    featureID: featureID,
                    role: sourceID.role,
                    ordinal: ordinal
                )
                guard subshapes[output] == nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Exact pattern disjoint aggregation produced a duplicate output identity."
                    )
                }
                subshapes[output] = reference
                temporaryLineage[output] = TopologyLineage(
                    output: output,
                    parents: [sourceID],
                    relation: .preserved
                )
            }
        }
        return Operand(
            bodyID: bodyID,
            brep: resultModel,
            subshapes: subshapes,
            lineage: temporaryLineage
        )
    }

    private func reduceInteractionGroups(
        _ groups: [[Operand]],
        finalFeatureID: FeatureID,
        ancestry: inout [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> Operand {
        var reducedGroups: [Operand] = []
        var stageOrdinal: UInt64 = 0
        for group in groups {
            guard var accumulator = group.first else {
                throw FeatureEvaluationError.invalidGraph(
                    "Exact pattern interaction partition contains an empty group."
                )
            }
            for operand in group.dropFirst() {
                let publishesFinalResult = groups.count == 1
                    && operand.bodyID == group.last?.bodyID
                let operationFeatureID = publishesFinalResult
                    ? finalFeatureID
                    : featureEvaluationStageID(
                    featureID: finalFeatureID,
                    domain: .patternUnion,
                    ordinal: stageOrdinal
                )
                accumulator = try union(
                    operands: [accumulator, operand],
                    operationFeatureID: operationFeatureID,
                    tolerance: tolerance
                )
                if publishesFinalResult == false {
                    ancestry = try mergedLineage([ancestry, accumulator.lineage])
                    stageOrdinal += 1
                }
            }
            reducedGroups.append(accumulator)
        }
        if reducedGroups.count == 1, let result = reducedGroups.first {
            return result
        }
        let combinedModel = try BRepModelCombiner().combined(reducedGroups.map(\.brep))
        return try disjointAggregate(
            operands: reducedGroups,
            combinedModel: combinedModel,
            featureID: finalFeatureID,
            tolerance: tolerance
        )
    }

    private func interactionGroups(
        operands: [Operand],
        interactions: [BodyMaterialInteraction]
    ) throws -> [[Operand]] {
        let operandByBodyID = Dictionary(uniqueKeysWithValues: operands.map {
            ($0.bodyID, $0)
        })
        let ordinalByBodyID = Dictionary(uniqueKeysWithValues: operands.enumerated().map {
            ($0.element.bodyID, $0.offset)
        })
        var adjacency = Dictionary(uniqueKeysWithValues: operands.map {
            ($0.bodyID, Set<BodyID>())
        })
        for interaction in interactions {
            guard interaction.firstBodyID != interaction.secondBodyID,
                  operandByBodyID[interaction.firstBodyID] != nil,
                  operandByBodyID[interaction.secondBodyID] != nil else {
                throw FeatureEvaluationError.invalidGraph(
                    "Exact pattern material interaction references an invalid operand pair."
                )
            }
            adjacency[interaction.firstBodyID, default: []].insert(
                interaction.secondBodyID
            )
            adjacency[interaction.secondBodyID, default: []].insert(
                interaction.firstBodyID
            )
        }
        var visited = Set<BodyID>()
        var groups: [[Operand]] = []
        for operand in operands where visited.contains(operand.bodyID) == false {
            visited.insert(operand.bodyID)
            var bodyIDs = [operand.bodyID]
            var cursor = 0
            while cursor < bodyIDs.count {
                let bodyID = bodyIDs[cursor]
                cursor += 1
                let neighbors = adjacency[bodyID, default: []].sorted {
                    ordinalByBodyID[$0, default: .max]
                        < ordinalByBodyID[$1, default: .max]
                }
                for neighbor in neighbors where visited.insert(neighbor).inserted {
                    bodyIDs.append(neighbor)
                }
            }
            groups.append(try bodyIDs.map { bodyID in
                guard let operand = operandByBodyID[bodyID] else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Exact pattern interaction partition lost an operand."
                    )
                }
                return operand
            })
        }
        return groups
    }

    private func union(
        operands: [Operand],
        operationFeatureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Operand {
        guard let tool = operands.last else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: operationFeatureID,
                tolerance: tolerance,
                message: "Exact pattern union has no operands."
            )
        }
        let targets = Array(operands.dropLast())
        let model = try BRepModelCombiner().combined(operands.map(\.brep))
        let subshapes = try mergedSubshapes(operands.map(\.subshapes))
        let lineage = try mergedLineage(operands.map(\.lineage))
        let result = try applicator.apply(
            operation: .union,
            targetBodyIDs: targets.map(\.bodyID),
            toolBodyID: tool.bodyID,
            keepTools: false,
            featureID: operationFeatureID,
            model: model,
            subshapes: subshapes,
            toolSubshapes: tool.subshapes,
            inputLineage: lineage,
            tolerance: tolerance
        )
        let bodyIDs = Set(result.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(bodyID) = reference else { return nil }
            return bodyID
        })
        guard bodyIDs.count == 1, let bodyID = bodyIDs.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: operationFeatureID,
                tolerance: tolerance,
                message: "Exact pattern union must publish exactly one result body."
            )
        }
        return Operand(
            bodyID: bodyID,
            brep: result.brep,
            subshapes: result.subshapes,
            lineage: result.lineage
        )
    }

    private func mergedSubshapes(
        _ maps: [[SubshapeID: TopologyReference]]
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [:]
        for map in maps {
            for (subshapeID, reference) in map {
                guard result[subshapeID] == nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Exact pattern instances produced a duplicate temporary subshape identity."
                    )
                }
                result[subshapeID] = reference
            }
        }
        return result
    }

    private func mergedLineage(
        _ maps: [[SubshapeID: TopologyLineage]]
    ) throws -> [SubshapeID: TopologyLineage] {
        var result: [SubshapeID: TopologyLineage] = [:]
        for map in maps {
            for (subshapeID, entry) in map {
                guard result[subshapeID] == nil else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Exact pattern evaluation produced a duplicate temporary lineage identity."
                    )
                }
                result[subshapeID] = entry
            }
        }
        return result
    }

    private func collapsedLineage(
        _ finalLineage: [SubshapeID: TopologyLineage],
        through ancestry: [SubshapeID: TopologyLineage],
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [SubshapeID: TopologyLineage] {
        var parentsByOutput: [SubshapeID: [SubshapeID]] = [:]
        for (output, entry) in finalLineage {
            var parents = Set<SubshapeID>()
            for parent in entry.parents {
                try collectPublishedParents(
                    of: parent,
                    ancestry: ancestry,
                    visited: [],
                    into: &parents,
                    tolerance: tolerance
                )
            }
            guard parents.allSatisfy({ $0.featureID != featureID }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: featureID,
                    subshapeID: output,
                    tolerance: tolerance,
                    message: "Exact pattern lineage retained an internal same-feature parent."
                )
            }
            parentsByOutput[output] = parents.sorted()
        }
        var parentUseCount: [SubshapeID: Int] = [:]
        for parents in parentsByOutput.values {
            for parent in parents {
                parentUseCount[parent, default: 0] += 1
            }
        }
        return Dictionary(uniqueKeysWithValues: parentsByOutput.map { output, parents in
            let relation: TopologyLineageRelation
            if parents.isEmpty {
                relation = .generated
            } else if parents.count > 1 {
                relation = .merged
            } else if parentUseCount[parents[0], default: 0] > 1 {
                relation = .split
            } else {
                relation = .preserved
            }
            return (
                output,
                TopologyLineage(output: output, parents: parents, relation: relation)
            )
        })
    }

    private func collectPublishedParents(
        of subshapeID: SubshapeID,
        ancestry: [SubshapeID: TopologyLineage],
        visited: Set<SubshapeID>,
        into result: inout Set<SubshapeID>,
        tolerance: ModelingTolerance
    ) throws {
        guard visited.contains(subshapeID) == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                subshapeID: subshapeID,
                tolerance: tolerance,
                message: "Exact pattern intermediate lineage contains a cycle."
            )
        }
        guard let entry = ancestry[subshapeID] else {
            result.insert(subshapeID)
            return
        }
        guard entry.parents.isEmpty == false else {
            return
        }
        var nextVisited = visited
        nextVisited.insert(subshapeID)
        for parent in entry.parents {
            try collectPublishedParents(
                of: parent,
                ancestry: ancestry,
                visited: nextVisited,
                into: &result,
                tolerance: tolerance
            )
        }
    }
}
