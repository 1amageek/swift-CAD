import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections

package struct SourceBRepFacePatchBuilder {
    package struct Result {
        package let patch: BRepSewingFacePatch
        package let stableKeys: [TopologyReference: BRepSewingStableKey]
    }

    package init() {}

    package func build(
        faceID: FaceID,
        stableID: String,
        from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Result {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard stableID.isEmpty == false,
              let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingReference(
                "Source face-patch extraction references missing face geometry.",
                tolerance: tolerance
            )
        }
        try reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride, using: &execution)
        var stableKeys: [TopologyReference: BRepSewingStableKey] = [
            .face(faceID): .face(stableID),
        ]
        var sewingLoops: [BRepSewingLoop] = []
        try reserve(count: face.loops.count, stride: MemoryLayout<BRepSewingLoop>.stride, using: &execution)
        sewingLoops.reserveCapacity(face.loops.count)
        for (loopIndex, loopID) in face.loops.enumerated() {
            try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else {
                throw missingReference(
                    "Source face-patch extraction references a missing loop.",
                    tolerance: tolerance
                )
            }
            try identity(base: stableID, suffixBytes: 6, ordinal: loopIndex, using: &execution)
            let loopStableID = "\(stableID):loop:\(loopIndex)"
            var sewingEdges: [BRepSewingEdge] = []
            try reserve(count: loop.edges.count, stride: MemoryLayout<BRepSewingEdge>.stride, using: &execution)
            sewingEdges.reserveCapacity(loop.edges.count)
            for (useIndex, coedge) in loop.edges.enumerated() {
                try execution.consumeWork(1)
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      let storedStart = model.vertices[edge.startVertexID]?.point,
                      let storedEnd = model.vertices[edge.endVertexID]?.point,
                      let trim = edge.trim,
                      let pcurve = coedge.surfaceParameterCurve else {
                    throw missingReference(
                        "Exact source face-patch extraction requires edge geometry, vertices, and a face-local pcurve.",
                        tolerance: tolerance
                    )
                }
                try identity(base: loopStableID, suffixBytes: 10, ordinal: useIndex, using: &execution)
                let edgeStableID = "\(loopStableID):edge-use:\(useIndex)"
                let oriented = orientedEdge(
                    edge: edge,
                    trim: trim,
                    storedStart: storedStart,
                    storedEnd: storedEnd,
                    orientation: coedge.orientation
                )
                // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded patch-copy callers
                // pay actual source traversal and output payload admission here.
                // Sewing ancestry canonicalization now forwards the same ledger.
                // Stable-key bucket metadata and complete modified-patch validation
                // still require their producer admission before whole ledger closure.
                try sewingEdges.append(BRepSewingEdge(
                    stableID: edgeStableID,
                    curve: curve,
                    startParameter: oriented.startParameter,
                    endParameter: oriented.endParameter,
                    startPoint: oriented.startPoint,
                    endPoint: oriented.endPoint,
                    surfaceParameterCurve: pcurve,
                    parentSubshapeIDs: sourceSubshapeIDs(
                        for: .edge(edge.id),
                        in: sourceSubshapes, using: &execution
                    ),
                    startVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.startVertexID),
                        in: sourceSubshapes, using: &execution
                    ),
                    endVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.endVertexID),
                        in: sourceSubshapes, using: &execution
                    ),
                    using: &execution
                ))
                try execution.consumeWork(1)
                if stableKeys[.edge(edge.id)] == nil {
                    try reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride, using: &execution)
                    stableKeys[.edge(edge.id)] = .edge(edgeStableID)
                }
                try execution.consumeWork(1)
                if stableKeys[.vertex(oriented.startVertexID)] == nil {
                    try reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride, using: &execution)
                    stableKeys[.vertex(oriented.startVertexID)] = .startVertex(edge: edgeStableID)
                }
                try execution.consumeWork(1)
                if stableKeys[.vertex(oriented.endVertexID)] == nil {
                    try reserve(count: 1, stride: MemoryLayout<TopologyReference>.stride + MemoryLayout<BRepSewingStableKey>.stride, using: &execution)
                    stableKeys[.vertex(oriented.endVertexID)] = .endVertex(edge: edgeStableID)
                }
            }
            sewingLoops.append(BRepSewingLoop(
                stableID: loopStableID,
                role: loop.role,
                edges: sewingEdges
            ))
        }
        return try Result(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: face.orientation,
                loops: sewingLoops,
                parentSubshapeIDs: sourceSubshapeIDs(
                    for: .face(faceID),
                    in: sourceSubshapes, using: &execution
                ),
                using: &execution
            ),
            stableKeys: stableKeys
        )
    }

    package func build(faceID: FaceID, stableID: String, from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference], tolerance: ModelingTolerance) throws -> Result {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try build(faceID: faceID, stableID: stableID, from: model,
            sourceSubshapes: sourceSubshapes, tolerance: tolerance, using: &execution)
    }

    private func orientedEdge(
        edge: Edge,
        trim: CurveTrim,
        storedStart: Point3D,
        storedEnd: Point3D,
        orientation: Orientation
    ) -> OrientedEdge {
        switch orientation {
        case .forward:
            return OrientedEdge(
                startParameter: trim.startParameter,
                endParameter: trim.endParameter,
                startPoint: storedStart,
                endPoint: storedEnd,
                startVertexID: edge.startVertexID,
                endVertexID: edge.endVertexID
            )
        case .reversed:
            return OrientedEdge(
                startParameter: trim.endParameter,
                endParameter: trim.startParameter,
                startPoint: storedEnd,
                endPoint: storedStart,
                startVertexID: edge.endVertexID,
                endVertexID: edge.startVertexID
            )
        }
    }

    private func sourceSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference],
        using execution: inout OriginalQueryExecution
    ) throws -> [SubshapeID] {
        var count = 0
        for (_, candidate) in sourceSubshapes {
            try execution.consumeWork(1)
            if candidate == reference {
                let next = count.addingReportingOverflow(1)
                guard !next.overflow else { throw ExactScalarFailure.countOverflow }
                count = next.partialValue
            }
        }
        try reserve(count: count, stride: MemoryLayout<SubshapeID>.stride, using: &execution)
        var result: [SubshapeID] = []
        result.reserveCapacity(count)
        for (subshapeID, candidate) in sourceSubshapes {
            try execution.consumeWork(1)
            if candidate == reference { result.append(subshapeID) }
        }
        return result
    }

    private func reserve(count: Int, stride: Int, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.retainStorage(count: count, stride: stride)
    }

    private func identity(base: String, suffixBytes: Int, ordinal: Int,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        var digits = 1, value = ordinal
        while value >= 10 { try execution.consumeWork(1); digits += 1; value /= 10 }
        let baseCount = base.utf8.count.addingReportingOverflow(suffixBytes)
        let total = baseCount.partialValue.addingReportingOverflow(digits)
        guard ordinal >= 0, !baseCount.overflow, !total.overflow else { throw ExactScalarFailure.countOverflow }
        try reserve(count: total.partialValue, stride: MemoryLayout<UInt8>.stride, using: &execution)
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private struct OrientedEdge {
        let startParameter: Double
        let endParameter: Double
        let startPoint: Point3D
        let endPoint: Point3D
        let startVertexID: VertexID
        let endVertexID: VertexID
    }
}
