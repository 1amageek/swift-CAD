import CADCore
import CADGeometry
import CADIR
import CADTopology

struct BRepDisjointUnionEvaluator: Sendable {
    func plan(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        separation: BRepBodySeparation? = nil
    , using execution: inout OriginalQueryExecution) throws -> BRepDisjointUnionPlan {
        try execution.consumeWork(1)
        try tolerance.validate()
        var operands: [BRepDisjointUnionOperand] = []
        for (index, bodyID) in targetBodyIDs.enumerated() {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(BRepDisjointUnionOperand(role: .target(index), bodyID: bodyID), to: &operands, using: &execution)
        }
        try OriginalParameterQueryStorage.append(BRepDisjointUnionOperand(role: .tool, bodyID: toolBodyID), to: &operands, using: &execution)
        try validateSeparatedSolidOperands(
            operands,
            in: model,
            tolerance: tolerance,
            separation: separation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID
        , using: &execution)
        let topology = try topologySummary(for: operands, in: model, using: &execution)
        return BRepDisjointUnionPlan(
            operands: operands,
            summary: BRepBooleanPlan(
                operandKind: .separatedSolidBodies,
                outputTopologyKind: .disjointSolidUnion,
                topologyNameSchemes: [.body, .copiedSourceTopology],
                topologySlots: topology.slots,
                topologyCounts: topology.counts,
                targetCellCount: targetBodyIDs.count,
                toolCellCount: 1,
                resultPrimitiveCount: operands.count
            )
        )
    }

    func addResultBody(
        plan: BRepDisjointUnionPlan,
        featureID: FeatureID,
        to model: inout BRepModel
    , using execution: inout OriginalQueryExecution) throws -> [SubshapeID: TopologyReference] {
        try execution.consumeWork(1)
        var copier = BRepDisjointUnionTopologyCopier(
            sourceModel: model,
            featureID: featureID
        )
        let result = try copier.copy(operands: plan.operands, using: &execution)
        model = result.model
        return result.subshapes
    }

    private func validateSeparatedSolidOperands(
        _ operands: [BRepDisjointUnionOperand],
        in model: BRepModel,
        tolerance: ModelingTolerance,
        separation: BRepBodySeparation?,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard operands.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Disjoint B-rep union requires at least two operands.")
        }
        for operand in operands {
            try execution.consumeWork(1)
            guard let body = model.bodies[operand.bodyID] else {
                throw TopologyError.missingReference("Missing boolean body \(operand.bodyID).")
            }
            guard body.kind == .solid else {
                throw KernelError.unsupportedEvaluation(
                    tolerance: tolerance,
                    message: "Disjoint B-rep union requires solid operands."
                )
            }
        }
        if let separation {
            try separation.validate(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                tolerance: tolerance
            )
            return
        }
        let bounds = try OriginalParameterQueryStorage.map(operands, using: &execution) { operand, execution in
            try BRepBodyBoundingBoxBuilder().bounds(
                for: operand.bodyID,
                in: model,
                tolerance: tolerance
            , using: &execution)
        }
        for firstIndex in bounds.indices {
            try execution.consumeWork(1)
            for secondIndex in bounds.indices where secondIndex > firstIndex {
            try execution.consumeWork(1)
                guard bounds[firstIndex].intersects(
                    bounds[secondIndex],
                    tolerance: tolerance.distance
                ) == false else {
                    throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                        "Disjoint B-rep union currently requires operand bounding boxes to be separated."
                    )
                }
            }
        }
    }

    private func topologySummary(
        for operands: [BRepDisjointUnionOperand],
        in model: BRepModel
    , using execution: inout OriginalQueryExecution) throws -> BRepDisjointUnionTopologySummary {
        try execution.consumeWork(1)
        var slots: [BooleanEvaluationTopologySlot] = []
        try OriginalParameterQueryStorage.append(BooleanEvaluationTopologySlot(role: .body), to: &slots, using: &execution)
        var shellCount = 0
        var faceCount = 0
        var loopCount = 0
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for operand in operands {
            try execution.consumeWork(1)
            let references = try BRepDisjointUnionOperandTopologyReferences(
                operand: operand,
                model: model
            , using: &execution)
            let shellCountNext = shellCount.addingReportingOverflow(references.shellIDs.count)
            guard !shellCountNext.overflow else { throw ExactScalarFailure.countOverflow }
            shellCount = shellCountNext.partialValue
            let faceCountNext = faceCount.addingReportingOverflow(references.faceIDs.count)
            guard !faceCountNext.overflow else { throw ExactScalarFailure.countOverflow }
            faceCount = faceCountNext.partialValue
            let loopCountNext = loopCount.addingReportingOverflow(references.loopIDs.count)
            guard !loopCountNext.overflow else { throw ExactScalarFailure.countOverflow }
            loopCount = loopCountNext.partialValue
            for id in references.edgeIDs {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(id, in: &edgeIDs, using: &execution) }
            for id in references.vertexIDs {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.insert(id, in: &vertexIDs, using: &execution) }
            for index in references.vertexIDs.indices {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(BooleanEvaluationTopologySlot(role: .vertex,
                    subshape: operand.subshape("vertex", index: index)), to: &slots, using: &execution)
            }
            for index in references.edgeIDs.indices {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(BooleanEvaluationTopologySlot(role: .edge,
                    subshape: operand.subshape("edge", index: index)), to: &slots, using: &execution)
            }
            for index in references.faceIDs.indices {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(BooleanEvaluationTopologySlot(role: .sideFace,
                    subshape: operand.subshape("face", index: index)), to: &slots, using: &execution)
            }
        }

        return BRepDisjointUnionTopologySummary(
            counts: BooleanEvaluationTopologyCounts(
                bodyCount: 1,
                shellCount: shellCount,
                faceCount: faceCount,
                loopCount: loopCount,
                edgeCount: edgeIDs.count,
                vertexCount: vertexIDs.count
            ),
            slots: slots
        )
    }
}

struct BRepDisjointUnionPlan: Sendable {
    var operands: [BRepDisjointUnionOperand]
    var summary: BRepBooleanPlan
}

struct BRepDisjointUnionOperand: Sendable, Hashable {
    enum Role: Sendable, Hashable {
        case target(Int)
        case tool
    }

    var role: Role
    var bodyID: BodyID

    func subshape(_ kind: String, index: Int) -> String {
        "copy:\(roleSubshape):\(kind):\(index)"
    }

    private var roleSubshape: String {
        switch role {
        case let .target(index):
            return "target:\(index)"
        case .tool:
            return "tool"
        }
    }
}

private struct BRepDisjointUnionTopologySummary: Sendable {
    var counts: BooleanEvaluationTopologyCounts
    var slots: [BooleanEvaluationTopologySlot]
}

private struct BRepDisjointUnionOperandTopologyReferences: Sendable {
    var solidComponents: [SolidShellComponent]
    var shellIDs: [ShellID]
    var faceIDs: [FaceID]
    var loopIDs: [LoopID]
    var edgeIDs: [EdgeID]
    var vertexIDs: [VertexID]

    init(operand: BRepDisjointUnionOperand, model: BRepModel, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let body = model.bodies[operand.bodyID] else {
            throw TopologyError.missingReference("Missing boolean body \(operand.bodyID).")
        }
        guard case .solid(let solidComponents) = body.topology else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: nil,
                message: "Disjoint union topology copying requires solid operands."
            )
        }
        self.solidComponents = solidComponents
        shellIDs = body.shellIDs
        var faceIDs: [FaceID] = []
        var loopIDs: [LoopID] = []
        var edgeIDs: [EdgeID] = []
        var vertexIDs: [VertexID] = []
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
            try execution.consumeWork(1)
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                try OriginalParameterQueryStorage.append(faceID, to: &faceIDs, using: &execution)
                for loopID in face.loops {
            try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                    }
                    try OriginalParameterQueryStorage.append(loopID, to: &loopIDs, using: &execution)
                    for orientedEdge in loop.edges {
            try execution.consumeWork(1)
                        try Self.appendUnique(orientedEdge.edgeID, to: &edgeIDs, using: &execution)
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            throw TopologyError.missingReference("Missing boolean edge \(orientedEdge.edgeID).")
                        }
                        try Self.appendUnique(edge.startVertexID, to: &vertexIDs, using: &execution)
                        try Self.appendUnique(edge.endVertexID, to: &vertexIDs, using: &execution)
                    }
                }
            }
        }
        self.faceIDs = faceIDs
        self.loopIDs = loopIDs
        self.edgeIDs = edgeIDs
        self.vertexIDs = vertexIDs
    }

    static func vertexIDs(for body: Body, model: BRepModel, using execution: inout OriginalQueryExecution) throws -> [VertexID] {
        try execution.consumeWork(1)
        var vertexIDs: [VertexID] = []
        for shellID in body.shellIDs {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
            try execution.consumeWork(1)
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                for loopID in face.loops {
            try execution.consumeWork(1)
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
            try execution.consumeWork(1)
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            throw TopologyError.missingReference("Missing boolean edge \(orientedEdge.edgeID).")
                        }
                        try appendUnique(edge.startVertexID, to: &vertexIDs, using: &execution)
                        try appendUnique(edge.endVertexID, to: &vertexIDs, using: &execution)
                    }
                }
            }
        }
        return vertexIDs
    }

    private static func appendUnique<T: Equatable>(_ value: T, to values: inout [T], using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard values.contains(value) == false else {
            return
        }
        try OriginalParameterQueryStorage.append(value, to: &values, using: &execution)
    }
}

private struct BRepDisjointUnionTopologyCopier {
    var sourceModel: BRepModel
    var featureID: FeatureID
    var resultModel: BRepModel
    var surfaceIDs: [SurfaceID: SurfaceID] = [:]
    var curveIDs: [CurveID: CurveID] = [:]
    var faceIDs: [FaceID: FaceID] = [:]
    var vertexIDs: [VertexID: VertexID] = [:]
    var edgeIDs: [EdgeID: EdgeID] = [:]

    init(sourceModel: BRepModel, featureID: FeatureID) {
        self.sourceModel = sourceModel
        self.featureID = featureID
        self.resultModel = sourceModel
    }

    mutating func copy(
        operands: [BRepDisjointUnionOperand]
    , using execution: inout OriginalQueryExecution) throws -> BRepDisjointUnionTopologyCopyResult {
        try execution.consumeWork(1)
        let bodyID = BodyID()
        var solidComponents: [SolidShellComponent] = []
        var subshapes: [SubshapeID: TopologyReference] = [:]
        try OriginalParameterQueryStorage.set(TopologyReference.body(bodyID),
            for: SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0),
            in: &subshapes, using: &execution)
        for operand in operands {
            try execution.consumeWork(1)
            let references = try BRepDisjointUnionOperandTopologyReferences(
                operand: operand,
                model: sourceModel
            , using: &execution)
            for component in references.solidComponents {
            try execution.consumeWork(1)
                try OriginalParameterQueryStorage.append(SolidShellComponent(
                    outerShellID: try copyShell(component.outerShellID, using: &execution),
                    voidShellIDs: try OriginalParameterQueryStorage.map(component.voidShellIDs, using: &execution) { id, execution in try copyShell(id, using: &execution) }
                ), to: &solidComponents, using: &execution)
            }
            try recordSubshapes(
                references: references,
                operand: operand,
                subshapes: &subshapes
            , using: &execution)
        }
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(BodyID, Body)>.stride)
        resultModel.bodies[bodyID] = Body(
            id: bodyID,
            solidComponents: solidComponents
        )
        return BRepDisjointUnionTopologyCopyResult(
            model: resultModel,
            subshapes: subshapes
        )
    }

    private mutating func copyShell(
        _ sourceShellID: ShellID,
     using execution: inout OriginalQueryExecution) throws -> ShellID {
        try execution.consumeWork(1)
        guard let sourceShell = sourceModel.shells[sourceShellID] else {
            throw TopologyError.missingReference("Missing boolean shell \(sourceShellID).")
        }
        let shellID = ShellID()
        let faceIDs = try OriginalParameterQueryStorage.map(sourceShell.faceIDs, using: &execution) { id, execution in try copyFace(id, using: &execution) }
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(ShellID, Shell)>.stride)
        resultModel.shells[shellID] = Shell(
            id: shellID,
            faceIDs: faceIDs,
            orientation: sourceShell.orientation
        )
        return shellID
    }

    private mutating func copyFace(
        _ sourceFaceID: FaceID
    , using execution: inout OriginalQueryExecution) throws -> FaceID {
        try execution.consumeWork(1)
        if let faceID = faceIDs[sourceFaceID] {
            return faceID
        }
        guard let sourceFace = sourceModel.faces[sourceFaceID] else {
            throw TopologyError.missingReference("Missing boolean face \(sourceFaceID).")
        }
        let faceID = FaceID()
        try OriginalParameterQueryStorage.set(faceID, for: sourceFaceID, in: &faceIDs, using: &execution)
        let surfaceID = try copySurface(sourceFace.surfaceID, using: &execution)
        let loopIDs = try OriginalParameterQueryStorage.map(sourceFace.loops, using: &execution) { id, execution in try copyLoop(id, using: &execution) }
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(FaceID, Face)>.stride)
        resultModel.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: loopIDs,
            orientation: sourceFace.orientation
        )
        return faceID
    }

    private mutating func copyLoop(_ sourceLoopID: LoopID, using execution: inout OriginalQueryExecution) throws -> LoopID {
        try execution.consumeWork(1)
        guard let sourceLoop = sourceModel.loops[sourceLoopID] else {
            throw TopologyError.missingReference("Missing boolean loop \(sourceLoopID).")
        }
        let loopID = LoopID()
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(LoopID, Loop)>.stride)
        resultModel.loops[loopID] = Loop(
            id: loopID,
            role: sourceLoop.role,
            edges: try OriginalParameterQueryStorage.map(sourceLoop.edges, using: &execution) { orientedEdge, execution in
                Coedge(
                    edgeID: try copyEdge(orientedEdge.edgeID, using: &execution),
                    orientation: orientedEdge.orientation,
                    surfaceParameterCurve: orientedEdge.surfaceParameterCurve
                )
            }
        )
        return loopID
    }

    private mutating func copyEdge(_ sourceEdgeID: EdgeID, using execution: inout OriginalQueryExecution) throws -> EdgeID {
        try execution.consumeWork(1)
        if let edgeID = edgeIDs[sourceEdgeID] {
            return edgeID
        }
        guard let sourceEdge = sourceModel.edges[sourceEdgeID] else {
            throw TopologyError.missingReference("Missing boolean edge \(sourceEdgeID).")
        }
        let edgeID = EdgeID()
        try OriginalParameterQueryStorage.set(edgeID, for: sourceEdgeID, in: &edgeIDs, using: &execution)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(EdgeID, Edge)>.stride)
        resultModel.edges[edgeID] = Edge(
            id: edgeID,
            curveID: try copyCurve(sourceEdge.curveID, using: &execution),
            startVertexID: try copyVertex(sourceEdge.startVertexID, using: &execution),
            endVertexID: try copyVertex(sourceEdge.endVertexID, using: &execution),
            trim: sourceEdge.trim
        )
        return edgeID
    }

    private mutating func copyVertex(_ sourceVertexID: VertexID, using execution: inout OriginalQueryExecution) throws -> VertexID {
        try execution.consumeWork(1)
        if let vertexID = vertexIDs[sourceVertexID] {
            return vertexID
        }
        guard let sourceVertex = sourceModel.vertices[sourceVertexID] else {
            throw TopologyError.missingReference("Missing boolean vertex \(sourceVertexID).")
        }
        let vertexID = VertexID()
        try OriginalParameterQueryStorage.set(vertexID, for: sourceVertexID, in: &vertexIDs, using: &execution)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(VertexID, Vertex)>.stride)
        resultModel.vertices[vertexID] = Vertex(id: vertexID, point: sourceVertex.point)
        return vertexID
    }

    private mutating func copyCurve(_ sourceCurveID: CurveID, using execution: inout OriginalQueryExecution) throws -> CurveID {
        try execution.consumeWork(1)
        if let curveID = curveIDs[sourceCurveID] {
            return curveID
        }
        guard let curve = sourceModel.geometry.curves[sourceCurveID] else {
            throw TopologyError.missingReference("Missing boolean curve \(sourceCurveID).")
        }
        let curveID = CurveID()
        try OriginalParameterQueryStorage.set(curveID, for: sourceCurveID, in: &curveIDs, using: &execution)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(CurveID, Curve3D)>.stride)
        resultModel.geometry.curves[curveID] = curve
        return curveID
    }

    private mutating func copySurface(_ sourceSurfaceID: SurfaceID, using execution: inout OriginalQueryExecution) throws -> SurfaceID {
        try execution.consumeWork(1)
        if let surfaceID = surfaceIDs[sourceSurfaceID] {
            return surfaceID
        }
        guard let surface = sourceModel.geometry.surfaces[sourceSurfaceID] else {
            throw TopologyError.missingReference("Missing boolean surface \(sourceSurfaceID).")
        }
        let surfaceID = SurfaceID()
        try OriginalParameterQueryStorage.set(surfaceID, for: sourceSurfaceID, in: &surfaceIDs, using: &execution)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<(SurfaceID, Surface3D)>.stride)
        resultModel.geometry.surfaces[surfaceID] = surface
        return surfaceID
    }

    private mutating func recordSubshapes(
        references: BRepDisjointUnionOperandTopologyReferences,
        operand: BRepDisjointUnionOperand,
        subshapes: inout [SubshapeID: TopologyReference]
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for (index, sourceVertexID) in references.vertexIDs.enumerated() {
            try execution.consumeWork(1)
            guard let vertexID = vertexIDs[sourceVertexID] else {
                throw TopologyError.missingReference("Missing copied boolean vertex \(sourceVertexID).")
            }
            try recordSubshape(
                role: .vertex,
                subshape: operand.subshape("vertex", index: index),
                reference: .vertex(vertexID),
                subshapes: &subshapes
            , using: &execution)
        }
        for (index, sourceEdgeID) in references.edgeIDs.enumerated() {
            try execution.consumeWork(1)
            guard let edgeID = edgeIDs[sourceEdgeID] else {
                throw TopologyError.missingReference("Missing copied boolean edge \(sourceEdgeID).")
            }
            try recordSubshape(
                role: .edge,
                subshape: operand.subshape("edge", index: index),
                reference: .edge(edgeID),
                subshapes: &subshapes
            , using: &execution)
        }
        for (index, sourceFaceID) in references.faceIDs.enumerated() {
            try execution.consumeWork(1)
            guard let faceID = faceIDs[sourceFaceID] else {
                throw TopologyError.missingReference("Missing copied boolean face \(sourceFaceID).")
            }
            try recordSubshape(
                role: .sideFace,
                subshape: operand.subshape("face", index: index),
                reference: .face(faceID),
                subshapes: &subshapes
            , using: &execution)
        }
    }

    private func recordSubshape(
        role: GeneratedSubshapeRole,
        subshape: String,
        reference: TopologyReference,
        subshapes: inout [SubshapeID: TopologyReference]
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        let subshapeID = SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: role.rawValue,
                subshapeRole: subshape
            ),
            ordinal: 0
        )
        guard subshapes[subshapeID] == nil else {
            throw FeatureEvaluationError.invalidGraph("Disjoint B-rep union generated subshape collision.")
        }
        try OriginalParameterQueryStorage.set(reference, for: subshapeID, in: &subshapes, using: &execution)
    }
}

private struct BRepDisjointUnionTopologyCopyResult {
    var model: BRepModel
    var subshapes: [SubshapeID: TopologyReference]
}
