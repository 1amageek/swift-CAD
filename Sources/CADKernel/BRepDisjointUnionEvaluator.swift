import CADCore
import CADIR
import CADTopology

struct BRepDisjointUnionEvaluator: Sendable {
    func plan(
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        separation: BRepBodySeparation? = nil
    ) throws -> BRepDisjointUnionPlan {
        try tolerance.validate()
        let operands = targetBodyIDs.enumerated().map { index, bodyID in
            BRepDisjointUnionOperand(role: .target(index), bodyID: bodyID)
        } + [
            BRepDisjointUnionOperand(role: .tool, bodyID: toolBodyID),
        ]
        try validateSeparatedSolidOperands(
            operands,
            in: model,
            tolerance: tolerance,
            separation: separation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID
        )
        let topology = try topologySummary(for: operands, in: model)
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
    ) throws -> [SubshapeID: TopologyReference] {
        var copier = BRepDisjointUnionTopologyCopier(
            sourceModel: model,
            featureID: featureID
        )
        let result = try copier.copy(operands: plan.operands)
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
    ) throws {
        guard operands.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Disjoint B-rep union requires at least two operands.")
        }
        if let separation {
            try separation.validate(
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                tolerance: tolerance
            )
            return
        }
        let bounds = try operands.map { operand in
            try BRepBodyBounds(bodyID: operand.bodyID, in: model, tolerance: tolerance)
        }
        for firstIndex in bounds.indices {
            for secondIndex in bounds.indices where secondIndex > firstIndex {
                guard bounds[firstIndex].isSeparated(from: bounds[secondIndex], tolerance: tolerance) else {
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
    ) throws -> BRepDisjointUnionTopologySummary {
        var slots = [BooleanEvaluationTopologySlot(role: .body)]
        var shellCount = 0
        var faceCount = 0
        var loopCount = 0
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for operand in operands {
            let references = try BRepDisjointUnionOperandTopologyReferences(
                operand: operand,
                model: model
            )
            shellCount += references.shellIDs.count
            faceCount += references.faceIDs.count
            loopCount += references.loopIDs.count
            edgeIDs.formUnion(references.edgeIDs)
            vertexIDs.formUnion(references.vertexIDs)
            slots.append(contentsOf: references.vertexIDs.enumerated().map { index, _ in
                BooleanEvaluationTopologySlot(
                    role: .vertex,
                    subshape: operand.subshape("vertex", index: index)
                )
            })
            slots.append(contentsOf: references.edgeIDs.enumerated().map { index, _ in
                BooleanEvaluationTopologySlot(
                    role: .edge,
                    subshape: operand.subshape("edge", index: index)
                )
            })
            slots.append(contentsOf: references.faceIDs.enumerated().map { index, _ in
                BooleanEvaluationTopologySlot(
                    role: .sideFace,
                    subshape: operand.subshape("face", index: index)
                )
            })
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

private struct BRepBodyBounds: Sendable {
    var minimum: Point3D
    var maximum: Point3D

    init(bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing boolean body \(bodyID).")
        }
        guard body.kind == .solid else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Disjoint B-rep union currently requires solid operands."
            )
        }
        let vertexIDs = try BRepDisjointUnionOperandTopologyReferences.vertexIDs(
            for: body,
            model: model
        )
        guard let firstVertexID = vertexIDs.first,
              let firstPoint = model.vertices[firstVertexID]?.point else {
            throw FeatureEvaluationError.emptyResult("Disjoint B-rep union operand has no vertices.")
        }
        minimum = firstPoint
        maximum = firstPoint
        for vertexID in vertexIDs.dropFirst() {
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Missing boolean vertex \(vertexID).")
            }
            minimum = Point3D(
                x: min(minimum.x, point.x),
                y: min(minimum.y, point.y),
                z: min(minimum.z, point.z)
            )
            maximum = Point3D(
                x: max(maximum.x, point.x),
                y: max(maximum.y, point.y),
                z: max(maximum.z, point.z)
            )
        }
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Disjoint B-rep union operand bounds collapsed.")
        }
    }

    func isSeparated(from other: BRepBodyBounds, tolerance: ModelingTolerance) -> Bool {
        maximum.x < other.minimum.x - tolerance.distance
            || other.maximum.x < minimum.x - tolerance.distance
            || maximum.y < other.minimum.y - tolerance.distance
            || other.maximum.y < minimum.y - tolerance.distance
            || maximum.z < other.minimum.z - tolerance.distance
            || other.maximum.z < minimum.z - tolerance.distance
    }
}

private struct BRepDisjointUnionOperandTopologyReferences: Sendable {
    var shellIDs: [ShellID]
    var faceIDs: [FaceID]
    var loopIDs: [LoopID]
    var edgeIDs: [EdgeID]
    var vertexIDs: [VertexID]

    init(operand: BRepDisjointUnionOperand, model: BRepModel) throws {
        guard let body = model.bodies[operand.bodyID] else {
            throw TopologyError.missingReference("Missing boolean body \(operand.bodyID).")
        }
        shellIDs = body.shellIDs
        var faceIDs: [FaceID] = []
        var loopIDs: [LoopID] = []
        var edgeIDs: [EdgeID] = []
        var vertexIDs: [VertexID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                faceIDs.append(faceID)
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                    }
                    loopIDs.append(loopID)
                    for orientedEdge in loop.edges {
                        Self.appendUnique(orientedEdge.edgeID, to: &edgeIDs)
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            throw TopologyError.missingReference("Missing boolean edge \(orientedEdge.edgeID).")
                        }
                        Self.appendUnique(edge.startVertexID, to: &vertexIDs)
                        Self.appendUnique(edge.endVertexID, to: &vertexIDs)
                    }
                }
            }
        }
        self.faceIDs = faceIDs
        self.loopIDs = loopIDs
        self.edgeIDs = edgeIDs
        self.vertexIDs = vertexIDs
    }

    static func vertexIDs(for body: Body, model: BRepModel) throws -> [VertexID] {
        var vertexIDs: [VertexID] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                    }
                    for orientedEdge in loop.edges {
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            throw TopologyError.missingReference("Missing boolean edge \(orientedEdge.edgeID).")
                        }
                        appendUnique(edge.startVertexID, to: &vertexIDs)
                        appendUnique(edge.endVertexID, to: &vertexIDs)
                    }
                }
            }
        }
        return vertexIDs
    }

    private static func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
        guard values.contains(value) == false else {
            return
        }
        values.append(value)
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
    ) throws -> BRepDisjointUnionTopologyCopyResult {
        let bodyID = BodyID()
        var shellIDs: [ShellID] = []
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(
                featureID: featureID,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0
            ): .body(bodyID),
        ]
        for operand in operands {
            let references = try BRepDisjointUnionOperandTopologyReferences(
                operand: operand,
                model: sourceModel
            )
            for shellID in references.shellIDs {
                shellIDs.append(try copyShell(shellID))
            }
            try recordSubshapes(
                references: references,
                operand: operand,
                subshapes: &subshapes
            )
        }
        resultModel.bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .solid)
        return BRepDisjointUnionTopologyCopyResult(
            model: resultModel,
            subshapes: subshapes
        )
    }

    private mutating func copyShell(
        _ sourceShellID: ShellID,
    ) throws -> ShellID {
        guard let sourceShell = sourceModel.shells[sourceShellID] else {
            throw TopologyError.missingReference("Missing boolean shell \(sourceShellID).")
        }
        let shellID = ShellID()
        let faceIDs = try sourceShell.faceIDs.map { try copyFace($0) }
        resultModel.shells[shellID] = Shell(
            id: shellID,
            faceIDs: faceIDs,
            orientation: sourceShell.orientation
        )
        return shellID
    }

    private mutating func copyFace(
        _ sourceFaceID: FaceID
    ) throws -> FaceID {
        if let faceID = faceIDs[sourceFaceID] {
            return faceID
        }
        guard let sourceFace = sourceModel.faces[sourceFaceID] else {
            throw TopologyError.missingReference("Missing boolean face \(sourceFaceID).")
        }
        let faceID = FaceID()
        faceIDs[sourceFaceID] = faceID
        let surfaceID = try copySurface(sourceFace.surfaceID)
        let loopIDs = try sourceFace.loops.map { try copyLoop($0) }
        resultModel.faces[faceID] = Face(
            id: faceID,
            surfaceID: surfaceID,
            loops: loopIDs,
            orientation: sourceFace.orientation
        )
        return faceID
    }

    private mutating func copyLoop(_ sourceLoopID: LoopID) throws -> LoopID {
        guard let sourceLoop = sourceModel.loops[sourceLoopID] else {
            throw TopologyError.missingReference("Missing boolean loop \(sourceLoopID).")
        }
        let loopID = LoopID()
        resultModel.loops[loopID] = Loop(
            id: loopID,
            role: sourceLoop.role,
            edges: try sourceLoop.edges.map { orientedEdge in
                Coedge(
                    edgeID: try copyEdge(orientedEdge.edgeID),
                    orientation: orientedEdge.orientation,
                    surfaceParameterCurve: orientedEdge.surfaceParameterCurve
                )
            }
        )
        return loopID
    }

    private mutating func copyEdge(_ sourceEdgeID: EdgeID) throws -> EdgeID {
        if let edgeID = edgeIDs[sourceEdgeID] {
            return edgeID
        }
        guard let sourceEdge = sourceModel.edges[sourceEdgeID] else {
            throw TopologyError.missingReference("Missing boolean edge \(sourceEdgeID).")
        }
        let edgeID = EdgeID()
        edgeIDs[sourceEdgeID] = edgeID
        resultModel.edges[edgeID] = Edge(
            id: edgeID,
            curveID: try copyCurve(sourceEdge.curveID),
            startVertexID: try copyVertex(sourceEdge.startVertexID),
            endVertexID: try copyVertex(sourceEdge.endVertexID),
            trim: sourceEdge.trim
        )
        return edgeID
    }

    private mutating func copyVertex(_ sourceVertexID: VertexID) throws -> VertexID {
        if let vertexID = vertexIDs[sourceVertexID] {
            return vertexID
        }
        guard let sourceVertex = sourceModel.vertices[sourceVertexID] else {
            throw TopologyError.missingReference("Missing boolean vertex \(sourceVertexID).")
        }
        let vertexID = VertexID()
        vertexIDs[sourceVertexID] = vertexID
        resultModel.vertices[vertexID] = Vertex(id: vertexID, point: sourceVertex.point)
        return vertexID
    }

    private mutating func copyCurve(_ sourceCurveID: CurveID) throws -> CurveID {
        if let curveID = curveIDs[sourceCurveID] {
            return curveID
        }
        guard let curve = sourceModel.geometry.curves[sourceCurveID] else {
            throw TopologyError.missingReference("Missing boolean curve \(sourceCurveID).")
        }
        let curveID = CurveID()
        curveIDs[sourceCurveID] = curveID
        resultModel.geometry.curves[curveID] = curve
        return curveID
    }

    private mutating func copySurface(_ sourceSurfaceID: SurfaceID) throws -> SurfaceID {
        if let surfaceID = surfaceIDs[sourceSurfaceID] {
            return surfaceID
        }
        guard let surface = sourceModel.geometry.surfaces[sourceSurfaceID] else {
            throw TopologyError.missingReference("Missing boolean surface \(sourceSurfaceID).")
        }
        let surfaceID = SurfaceID()
        surfaceIDs[sourceSurfaceID] = surfaceID
        resultModel.geometry.surfaces[surfaceID] = surface
        return surfaceID
    }

    private mutating func recordSubshapes(
        references: BRepDisjointUnionOperandTopologyReferences,
        operand: BRepDisjointUnionOperand,
        subshapes: inout [SubshapeID: TopologyReference]
    ) throws {
        for (index, sourceVertexID) in references.vertexIDs.enumerated() {
            guard let vertexID = vertexIDs[sourceVertexID] else {
                throw TopologyError.missingReference("Missing copied boolean vertex \(sourceVertexID).")
            }
            try recordSubshape(
                role: .vertex,
                subshape: operand.subshape("vertex", index: index),
                reference: .vertex(vertexID),
                subshapes: &subshapes
            )
        }
        for (index, sourceEdgeID) in references.edgeIDs.enumerated() {
            guard let edgeID = edgeIDs[sourceEdgeID] else {
                throw TopologyError.missingReference("Missing copied boolean edge \(sourceEdgeID).")
            }
            try recordSubshape(
                role: .edge,
                subshape: operand.subshape("edge", index: index),
                reference: .edge(edgeID),
                subshapes: &subshapes
            )
        }
        for (index, sourceFaceID) in references.faceIDs.enumerated() {
            guard let faceID = faceIDs[sourceFaceID] else {
                throw TopologyError.missingReference("Missing copied boolean face \(sourceFaceID).")
            }
            try recordSubshape(
                role: .sideFace,
                subshape: operand.subshape("face", index: index),
                reference: .face(faceID),
                subshapes: &subshapes
            )
        }
    }

    private func recordSubshape(
        role: GeneratedSubshapeRole,
        subshape: String,
        reference: TopologyReference,
        subshapes: inout [SubshapeID: TopologyReference]
    ) throws {
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
        subshapes[subshapeID] = reference
    }
}

private struct BRepDisjointUnionTopologyCopyResult {
    var model: BRepModel
    var subshapes: [SubshapeID: TopologyReference]
}
