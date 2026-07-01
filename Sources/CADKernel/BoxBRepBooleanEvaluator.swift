import CADCore
import CADIR

public struct BoxBRepBooleanEvaluator: BRepBooleanEvaluating {
    public init() {}

    func plan(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoxBRepBooleanPlan {
        try makePlan(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        ).summary
    }

    public func evaluate(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        generatedNames: [PersistentName: TopologyReference],
        toolGeneratedNames: [PersistentName: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        let operationPlan = try makePlan(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            model: model,
            tolerance: tolerance
        )
        let resultShape = operationPlan.shape
        guard resultShape.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean operation produced no body.")
        }

        var resultModel = model
        var removedGeneratedNames = Set<PersistentName>()
        var resultGeneratedNames: [PersistentName: TopologyReference] = [:]

        if keepTools {
            resultGeneratedNames = try remappedToolGeneratedNames(toolGeneratedNames, featureID: featureID)
        } else {
            for targetBodyID in targetBodyIDs {
                removedGeneratedNames.formUnion(
                    generatedNamesReferencingBodyTopology(
                        bodyID: targetBodyID,
                        in: resultModel,
                        generatedNames: generatedNames
                    )
                )
                try removeBodyTopology(bodyID: targetBodyID, from: &resultModel)
            }
            removedGeneratedNames.formUnion(
                generatedNamesReferencingBodyTopology(
                    bodyID: toolBodyID,
                    in: resultModel,
                    generatedNames: generatedNames
                )
            )
            try removeBodyTopology(bodyID: toolBodyID, from: &resultModel)
        }

        let builder = AxisAlignedBoxBRepBuilder(tolerance: tolerance)
        let builtNames = try builder.addBody(
            shape: resultShape,
            featureID: featureID,
            to: &resultModel
        )
        for (name, reference) in builtNames {
            guard resultGeneratedNames[name] == nil else {
                throw FeatureEvaluationError.invalidGraph("Boolean generated persistent name collision.")
            }
            resultGeneratedNames[name] = reference
        }
        try resultModel.validate(tolerance: tolerance)
        return EvaluationResult(
            brep: resultModel,
            generatedNames: resultGeneratedNames,
            removedGeneratedNames: removedGeneratedNames
        )
    }

    private func makePlan(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoxBRepBooleanOperationPlan {
        try tolerance.validate()
        guard operation != .newBody else {
            throw FeatureEvaluationError.invalidGraph("B-rep boolean evaluation requires a target operation.")
        }
        guard Set(targetBodyIDs).count == targetBodyIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Boolean target body IDs must be unique.")
        }
        guard targetBodyIDs.contains(toolBodyID) == false else {
            throw FeatureEvaluationError.invalidGraph("Boolean tool body must be distinct from every target body.")
        }
        let targetOperands = try targetBodyIDs.map { bodyID in
            try OrthogonalSolidOperand(bodyID: bodyID, in: model, tolerance: tolerance)
        }
        let toolOperand = try OrthogonalSolidOperand(bodyID: toolBodyID, in: model, tolerance: tolerance)
        let targetCells = targetOperands.flatMap(\.cells)
        let toolCells = toolOperand.cells
        let resultShape = try bodyShape(
            for: operation,
            targets: targetCells,
            tool: toolCells,
            tolerance: tolerance
        )
        guard resultShape.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean operation produced no body.")
        }
        return BoxBRepBooleanOperationPlan(
            summary: BoxBRepBooleanPlan(
                operandKind: targetOperands.allSatisfy { $0.cells.count == 1 } && toolOperand.cells.count == 1
                    ? .axisAlignedBoxSolids
                    : .orthogonalCellUnionSolids,
                outputTopologyKind: resultShape.outputTopologyKind,
                topologyNameSchemes: resultShape.topologyNameSchemes,
                targetCellCount: targetCells.count,
                toolCellCount: toolCells.count,
                resultPrimitiveCount: resultShape.resultPrimitiveCount
            ),
            shape: resultShape
        )
    }

    private func bodyShape(
        for operation: SweepBooleanOperation,
        targets: [AxisAlignedBox],
        tool: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let targetCells = try normalizedCells(targets, tolerance: tolerance)
        let toolCells = try normalizedCells(tool, tolerance: tolerance)
        switch operation {
        case .newBody:
            throw FeatureEvaluationError.invalidGraph("B-rep boolean evaluation requires a target operation.")
        case .union:
            return try compactedShape(from: targetCells + toolCells, tolerance: tolerance)
        case .difference:
            if toolCells.count == 1 {
                return try differenceBoxes(targets: targetCells, tool: toolCells[0], tolerance: tolerance)
            }
            return try differenceCells(targets: targetCells, tools: toolCells, tolerance: tolerance)
        case .intersect:
            return try intersectCells(targets: targetCells, tools: toolCells, tolerance: tolerance)
        case .slice:
            return .boxes(try sliceCells(targets: targetCells, tools: toolCells, tolerance: tolerance))
        }
    }

    private func compactedShape(
        from boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let cells = try normalizedCells(boxes, tolerance: tolerance)
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean operation produced no body.")
        }
        if let singleBox = rectangularUnion(of: cells, tolerance: tolerance) {
            return .boxes([singleBox])
        }
        if boxesAreSeparated(cells, tolerance: tolerance) {
            return .boxes(cells)
        }
        return .orthogonalCellUnion(cells)
    }

    private func differenceBoxes(
        targets: [AxisAlignedBox],
        tool: AxisAlignedBox,
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        var result: [AxisAlignedBox] = []
        var frames: [ZThroughBoxFrame] = []
        for target in targets {
            let fragments = target.subtracting(tool, tolerance: tolerance)
            if fragments.isEmpty {
                continue
            }
            if let rectangularResult = rectangularUnion(of: fragments, tolerance: tolerance) {
                result.append(rectangularResult)
                continue
            }
            guard boxesAreSeparated(fragments, tolerance: tolerance) else {
                if let frame = target.zThroughFrame(cutBy: tool, tolerance: tolerance) {
                    frames.append(frame)
                    continue
                }
                return .orthogonalCellUnion(fragments)
            }
            result.append(contentsOf: fragments)
        }
        guard frames.isEmpty else {
            guard result.isEmpty, frames.count == 1 else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Box difference frame results cannot be mixed with other target fragments."
                )
            }
            return .zThroughFrame(frames[0])
        }
        if let rectangularResult = rectangularUnion(of: result, tolerance: tolerance) {
            return .boxes([rectangularResult])
        }
        guard boxesAreSeparated(result, tolerance: tolerance) else {
            return .orthogonalCellUnion(try normalizedCells(result, tolerance: tolerance))
        }
        return .boxes(result)
    }

    private func differenceCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        var fragments = targets
        for tool in tools {
            fragments = fragments.flatMap { fragment in
                fragment.subtracting(tool, tolerance: tolerance)
            }
            guard fragments.isEmpty == false else {
                throw FeatureEvaluationError.emptyResult("Boolean difference produced no body.")
            }
        }
        return try compactedShape(from: fragments, tolerance: tolerance)
    }

    private func intersectCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> BooleanBodyShape {
        let intersections = targets.flatMap { target in
            tools.compactMap { tool in
                target.intersection(with: tool, tolerance: tolerance)
            }
        }
        guard intersections.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean intersection produced no body.")
        }
        return try compactedShape(from: intersections, tolerance: tolerance)
    }

    private func sliceCells(
        targets: [AxisAlignedBox],
        tools: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> [AxisAlignedBox] {
        var result: [AxisAlignedBox] = []
        for target in targets {
            var fragments = [target]
            for tool in tools {
                fragments = fragments.flatMap { fragment in
                    fragment.sliced(by: tool, tolerance: tolerance)
                }
            }
            result.append(contentsOf: fragments)
        }
        let cells = try normalizedCells(result, tolerance: tolerance)
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Boolean slice produced no body.")
        }
        return cells
    }

    private func normalizedCells(
        _ boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) throws -> [AxisAlignedBox] {
        guard boxes.isEmpty == false else {
            return []
        }
        let xCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2,
              yCoordinates.count >= 2,
              zCoordinates.count >= 2 else {
            return []
        }
        var cells: [AxisAlignedBox] = []
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let minimum = Point3D(
                        x: xCoordinates[xIndex],
                        y: yCoordinates[yIndex],
                        z: zCoordinates[zIndex]
                    )
                    let maximum = Point3D(
                        x: xCoordinates[xIndex + 1],
                        y: yCoordinates[yIndex + 1],
                        z: zCoordinates[zIndex + 1]
                    )
                    let center = Point3D(
                        x: (minimum.x + maximum.x) * 0.5,
                        y: (minimum.y + maximum.y) * 0.5,
                        z: (minimum.z + maximum.z) * 0.5
                    )
                    guard boxes.contains(where: { $0.contains(center) }) else {
                        continue
                    }
                    cells.append(try AxisAlignedBox(minimum: minimum, maximum: maximum, tolerance: tolerance))
                }
            }
        }
        return cells
    }

    private func rectangularUnion(
        of boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) -> AxisAlignedBox? {
        guard let boundingBox = AxisAlignedBox.bounding(boxes) else {
            return nil
        }
        let unionVolume = AxisAlignedBox.unionVolume(of: boxes, tolerance: tolerance)
        let epsilon = max(tolerance.distance, 1.0e-12)
        guard abs(boundingBox.volume - unionVolume) <= epsilon * max(1.0, boundingBox.volume) else {
            return nil
        }
        return boundingBox
    }

    private func boxesAreSeparated(
        _ boxes: [AxisAlignedBox],
        tolerance: ModelingTolerance
    ) -> Bool {
        for firstIndex in boxes.indices {
            for secondIndex in boxes.indices where secondIndex > firstIndex {
                guard boxes[firstIndex].isSeparated(from: boxes[secondIndex], tolerance: tolerance) else {
                    return false
                }
            }
        }
        return true
    }

    private func generatedNamesReferencingBodyTopology(
        bodyID: BodyID,
        in model: BRepModel,
        generatedNames: [PersistentName: TopologyReference]
    ) -> Set<PersistentName> {
        let references = topologyReferences(for: bodyID, in: model)
        return Set(generatedNames.compactMap { name, reference in
            references.contains(reference) ? name : nil
        })
    }

    private func topologyReferences(for bodyID: BodyID, in model: BRepModel) -> Set<TopologyReference> {
        guard let body = model.bodies[bodyID] else {
            return []
        }
        var references: Set<TopologyReference> = [.body(bodyID)]
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                continue
            }
            for faceID in shell.faceIDs {
                references.insert(.face(faceID))
                guard let face = model.faces[faceID] else {
                    continue
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        continue
                    }
                    for orientedEdge in loop.edges {
                        references.insert(.edge(orientedEdge.edgeID))
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            continue
                        }
                        references.insert(.vertex(edge.startVertexID))
                        references.insert(.vertex(edge.endVertexID))
                    }
                }
            }
        }
        return references
    }

    private func removeBodyTopology(bodyID: BodyID, from model: inout BRepModel) throws {
        guard let body = model.bodies.removeValue(forKey: bodyID) else {
            throw TopologyError.missingReference("Missing boolean body \(bodyID).")
        }
        var surfaceIDs = Set<SurfaceID>()
        var curveIDs = Set<CurveID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for shellID in body.shellIDs {
            guard let shell = model.shells.removeValue(forKey: shellID) else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces.removeValue(forKey: faceID) else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                surfaceIDs.insert(face.surfaceID)
                for loopID in face.loops {
                    loopIDs.insert(loopID)
                }
            }
        }
        for loopID in loopIDs {
            guard let loop = model.loops.removeValue(forKey: loopID) else {
                throw TopologyError.missingReference("Missing boolean loop \(loopID).")
            }
            for orientedEdge in loop.edges {
                edgeIDs.insert(orientedEdge.edgeID)
            }
        }
        for edgeID in edgeIDs {
            guard let edge = model.edges.removeValue(forKey: edgeID) else {
                throw TopologyError.missingReference("Missing boolean edge \(edgeID).")
            }
            curveIDs.insert(edge.curveID)
            vertexIDs.insert(edge.startVertexID)
            vertexIDs.insert(edge.endVertexID)
        }
        for vertexID in vertexIDs {
            model.vertices.removeValue(forKey: vertexID)
        }
        for curveID in curveIDs {
            model.geometry.curves.removeValue(forKey: curveID)
        }
        for surfaceID in surfaceIDs {
            model.geometry.surfaces.removeValue(forKey: surfaceID)
        }
    }

    private func remappedToolGeneratedNames(
        _ generatedNames: [PersistentName: TopologyReference],
        featureID: FeatureID
    ) throws -> [PersistentName: TopologyReference] {
        var remapped: [PersistentName: TopologyReference] = [:]
        for (name, reference) in generatedNames {
            let tail: [NameComponent]
            if name.components.first == .feature(featureID) {
                tail = Array(name.components.dropFirst())
            } else {
                tail = name.components
            }
            let remappedName = PersistentName(components: [.feature(featureID), .subshape("tool")] + tail)
            guard remapped[remappedName] == nil else {
                throw FeatureEvaluationError.invalidGraph("Boolean tool persistent name collision.")
            }
            remapped[remappedName] = reference
        }
        return remapped
    }
}

private struct BoxBRepBooleanOperationPlan: Sendable {
    var summary: BoxBRepBooleanPlan
    var shape: BooleanBodyShape
}

struct AxisAlignedBox: Sendable, Hashable {
    var minimum: Point3D
    var maximum: Point3D

    init(minimum: Point3D, maximum: Point3D, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            throw FeatureEvaluationError.emptyResult("Box boolean produced a collapsed body.")
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    init(bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing boolean target body \(bodyID).")
        }
        guard body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 6 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Box boolean evaluation currently requires one closed rectangular-prism body."
            )
        }

        var faceIDs = Set<FaceID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  case .plane = model.geometry.surfaces[face.surfaceID] else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Box boolean evaluation currently requires planar faces."
                )
            }
            faceIDs.insert(faceID)
            for loopID in face.loops {
                loopIDs.insert(loopID)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Missing boolean loop \(loopID).")
                }
                for orientedEdge in loop.edges {
                    edgeIDs.insert(orientedEdge.edgeID)
                }
            }
        }
        guard faceIDs.count == 6,
              loopIDs.count == 6,
              edgeIDs.count == 12 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Box boolean evaluation currently requires rectangular-prism topology."
            )
        }
        for edgeID in edgeIDs {
            guard let edge = model.edges[edgeID],
                  case .line = model.geometry.curves[edge.curveID] else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Box boolean evaluation currently requires linear edges."
                )
            }
            vertexIDs.insert(edge.startVertexID)
            vertexIDs.insert(edge.endVertexID)
        }
        guard vertexIDs.count == 8 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Box boolean evaluation currently requires eight box vertices."
            )
        }
        let points = try vertexIDs.map { vertexID -> Point3D in
            guard let point = model.vertices[vertexID]?.point else {
                throw TopologyError.missingReference("Missing boolean vertex \(vertexID).")
            }
            return point
        }
        let minimum = Point3D(
            x: points.map(\.x).min() ?? 0.0,
            y: points.map(\.y).min() ?? 0.0,
            z: points.map(\.z).min() ?? 0.0
        )
        let maximum = Point3D(
            x: points.map(\.x).max() ?? 0.0,
            y: points.map(\.y).max() ?? 0.0,
            z: points.map(\.z).max() ?? 0.0
        )
        try self.init(minimum: minimum, maximum: maximum, tolerance: tolerance)
        try validateCorners(points, tolerance: tolerance)
    }

    var volume: Double {
        (maximum.x - minimum.x) * (maximum.y - minimum.y) * (maximum.z - minimum.z)
    }

    func intersection(with other: AxisAlignedBox, tolerance: ModelingTolerance) -> AxisAlignedBox? {
        let minimum = Point3D(
            x: max(self.minimum.x, other.minimum.x),
            y: max(self.minimum.y, other.minimum.y),
            z: max(self.minimum.z, other.minimum.z)
        )
        let maximum = Point3D(
            x: min(self.maximum.x, other.maximum.x),
            y: min(self.maximum.y, other.maximum.y),
            z: min(self.maximum.z, other.maximum.z)
        )
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            return nil
        }
        return AxisAlignedBox(uncheckedMinimum: minimum, uncheckedMaximum: maximum)
    }

    func subtracting(_ tool: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        guard let intersection = intersection(with: tool, tolerance: tolerance) else {
            return [self]
        }
        return partitioned(by: intersection, tolerance: tolerance).filter { fragment in
            let center = fragment.center
            return intersection.contains(center) == false
        }
    }

    func sliced(by tool: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        guard let intersection = intersection(with: tool, tolerance: tolerance) else {
            return [self]
        }
        return partitioned(by: intersection, tolerance: tolerance)
    }

    fileprivate func zThroughFrame(cutBy tool: AxisAlignedBox, tolerance: ModelingTolerance) -> ZThroughBoxFrame? {
        guard let hole = intersection(with: tool, tolerance: tolerance),
              abs(hole.minimum.z - minimum.z) <= tolerance.distance,
              abs(hole.maximum.z - maximum.z) <= tolerance.distance,
              hole.minimum.x - minimum.x > tolerance.distance,
              maximum.x - hole.maximum.x > tolerance.distance,
              hole.minimum.y - minimum.y > tolerance.distance,
              maximum.y - hole.maximum.y > tolerance.distance else {
            return nil
        }
        return ZThroughBoxFrame(outer: self, hole: hole)
    }

    var center: Point3D {
        Point3D(
            x: (minimum.x + maximum.x) * 0.5,
            y: (minimum.y + maximum.y) * 0.5,
            z: (minimum.z + maximum.z) * 0.5
        )
    }

    private func partitioned(by intersection: AxisAlignedBox, tolerance: ModelingTolerance) -> [AxisAlignedBox] {
        var xCoordinates = uniqueSorted(
            [minimum.x, intersection.minimum.x, intersection.maximum.x, maximum.x],
            tolerance: tolerance
        )
        var yCoordinates = uniqueSorted(
            [minimum.y, intersection.minimum.y, intersection.maximum.y, maximum.y],
            tolerance: tolerance
        )
        var zCoordinates = uniqueSorted(
            [minimum.z, intersection.minimum.z, intersection.maximum.z, maximum.z],
            tolerance: tolerance
        )
        xCoordinates = xCoordinates.filter { $0 >= minimum.x - tolerance.distance && $0 <= maximum.x + tolerance.distance }
        yCoordinates = yCoordinates.filter { $0 >= minimum.y - tolerance.distance && $0 <= maximum.y + tolerance.distance }
        zCoordinates = zCoordinates.filter { $0 >= minimum.z - tolerance.distance && $0 <= maximum.z + tolerance.distance }
        var fragments: [AxisAlignedBox] = []
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let cellMinimum = Point3D(
                        x: xCoordinates[xIndex],
                        y: yCoordinates[yIndex],
                        z: zCoordinates[zIndex]
                    )
                    let cellMaximum = Point3D(
                        x: xCoordinates[xIndex + 1],
                        y: yCoordinates[yIndex + 1],
                        z: zCoordinates[zIndex + 1]
                    )
                    guard cellMaximum.x - cellMinimum.x > tolerance.distance,
                          cellMaximum.y - cellMinimum.y > tolerance.distance,
                          cellMaximum.z - cellMinimum.z > tolerance.distance else {
                        continue
                    }
                    fragments.append(AxisAlignedBox(
                        uncheckedMinimum: cellMinimum,
                        uncheckedMaximum: cellMaximum
                    ))
                }
            }
        }
        return fragments
    }

    func contains(_ point: Point3D) -> Bool {
        point.x >= minimum.x && point.x <= maximum.x
            && point.y >= minimum.y && point.y <= maximum.y
            && point.z >= minimum.z && point.z <= maximum.z
    }

    func isSeparated(from other: AxisAlignedBox, tolerance: ModelingTolerance) -> Bool {
        maximum.x < other.minimum.x - tolerance.distance
            || other.maximum.x < minimum.x - tolerance.distance
            || maximum.y < other.minimum.y - tolerance.distance
            || other.maximum.y < minimum.y - tolerance.distance
            || maximum.z < other.minimum.z - tolerance.distance
            || other.maximum.z < minimum.z - tolerance.distance
    }

    static func bounding(_ boxes: [AxisAlignedBox]) -> AxisAlignedBox? {
        guard let first = boxes.first else {
            return nil
        }
        return boxes.dropFirst().reduce(first) { partial, box in
            AxisAlignedBox(
                uncheckedMinimum: Point3D(
                    x: min(partial.minimum.x, box.minimum.x),
                    y: min(partial.minimum.y, box.minimum.y),
                    z: min(partial.minimum.z, box.minimum.z)
                ),
                uncheckedMaximum: Point3D(
                    x: max(partial.maximum.x, box.maximum.x),
                    y: max(partial.maximum.y, box.maximum.y),
                    z: max(partial.maximum.z, box.maximum.z)
                )
            )
        }
    }

    static func unionVolume(of boxes: [AxisAlignedBox], tolerance: ModelingTolerance) -> Double {
        let xCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(boxes.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2,
              yCoordinates.count >= 2,
              zCoordinates.count >= 2 else {
            return 0.0
        }
        var volume = 0.0
        for xIndex in 0..<(xCoordinates.count - 1) {
            for yIndex in 0..<(yCoordinates.count - 1) {
                for zIndex in 0..<(zCoordinates.count - 1) {
                    let center = Point3D(
                        x: (xCoordinates[xIndex] + xCoordinates[xIndex + 1]) * 0.5,
                        y: (yCoordinates[yIndex] + yCoordinates[yIndex + 1]) * 0.5,
                        z: (zCoordinates[zIndex] + zCoordinates[zIndex + 1]) * 0.5
                    )
                    guard boxes.contains(where: { $0.contains(center) }) else {
                        continue
                    }
                    volume += (xCoordinates[xIndex + 1] - xCoordinates[xIndex])
                        * (yCoordinates[yIndex + 1] - yCoordinates[yIndex])
                        * (zCoordinates[zIndex + 1] - zCoordinates[zIndex])
                }
            }
        }
        return volume
    }

    private init(uncheckedMinimum: Point3D, uncheckedMaximum: Point3D) {
        minimum = uncheckedMinimum
        maximum = uncheckedMaximum
    }

    private func validateCorners(_ points: [Point3D], tolerance: ModelingTolerance) throws {
        var cornerKeys = Set<String>()
        for point in points {
            let xKey = try axisKey(value: point.x, minimum: minimum.x, maximum: maximum.x, tolerance: tolerance)
            let yKey = try axisKey(value: point.y, minimum: minimum.y, maximum: maximum.y, tolerance: tolerance)
            let zKey = try axisKey(value: point.z, minimum: minimum.z, maximum: maximum.z, tolerance: tolerance)
            cornerKeys.insert("\(xKey):\(yKey):\(zKey)")
        }
        guard cornerKeys.count == 8 else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Box boolean evaluation currently requires axis-aligned box corners."
            )
        }
    }

    private func axisKey(
        value: Double,
        minimum: Double,
        maximum: Double,
        tolerance: ModelingTolerance
    ) throws -> String {
        if abs(value - minimum) <= tolerance.distance {
            return "min"
        }
        if abs(value - maximum) <= tolerance.distance {
            return "max"
        }
        throw FeatureEvaluationError.unsupportedOperation(
            "Box boolean evaluation currently requires axis-aligned box vertices."
        )
    }
}

private enum BooleanBodyShape: Sendable {
    case boxes([AxisAlignedBox])
    case orthogonalCellUnion([AxisAlignedBox])
    case zThroughFrame(ZThroughBoxFrame)

    var isEmpty: Bool {
        switch self {
        case let .boxes(boxes):
            return boxes.isEmpty
        case let .orthogonalCellUnion(cells):
            return cells.isEmpty
        case .zThroughFrame:
            return false
        }
    }

    var outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind {
        switch self {
        case .boxes(let boxes) where boxes.count == 1:
            return .singleBox
        case .boxes:
            return .separatedBoxes
        case .orthogonalCellUnion:
            return .orthogonalCellUnion
        case .zThroughFrame:
            return .zThroughFrame
        }
    }

    var resultPrimitiveCount: Int {
        switch self {
        case .boxes(let boxes):
            return boxes.count
        case .orthogonalCellUnion(let cells):
            return cells.count
        case .zThroughFrame:
            return 1
        }
    }

    var topologyNameSchemes: [BooleanEvaluationCapabilities.TopologyNameScheme] {
        switch self {
        case .boxes:
            return [
                .body,
                .boxVertices,
                .boxEdges,
                .boxFaces,
            ]
        case .orthogonalCellUnion:
            return [
                .body,
                .cellUnionVertices,
                .cellUnionEdges,
                .cellUnionFaces,
            ]
        case .zThroughFrame:
            return [
                .body,
                .frameOuterVertices,
                .frameHoleVertices,
                .frameOuterEdges,
                .frameHoleEdges,
                .frameBridgeEdges,
                .frameCapFaces,
                .frameOuterSideFaces,
                .frameHoleSideFaces,
            ]
        }
    }
}

private struct ZThroughBoxFrame: Sendable, Hashable {
    var outer: AxisAlignedBox
    var hole: AxisAlignedBox
}

private struct AxisAlignedBoxBRepBuilder {
    var tolerance: ModelingTolerance

    func addBody(
        shape: BooleanBodyShape,
        featureID: FeatureID,
        to model: inout BRepModel
    ) throws -> [PersistentName: TopologyReference] {
        try tolerance.validate()
        let bodyID = BodyID()
        var shellIDs: [ShellID] = []
        var generatedNames: [PersistentName: TopologyReference] = [
            persistentName(featureID, .body): .body(bodyID)
        ]
        switch shape {
        case let .boxes(boxes):
            guard boxes.isEmpty == false else {
                throw FeatureEvaluationError.emptyResult("Box builder requires at least one box.")
            }
            for (boxIndex, box) in boxes.enumerated() {
                let shellID = try addShell(
                    box: box,
                    boxIndex: boxIndex,
                    featureID: featureID,
                    to: &model,
                    generatedNames: &generatedNames
                )
                shellIDs.append(shellID)
            }
        case let .orthogonalCellUnion(cells):
            shellIDs.append(contentsOf: try addCellUnionShells(
                cells: cells,
                featureID: featureID,
                to: &model,
                generatedNames: &generatedNames
            ))
        case let .zThroughFrame(frame):
            let shellID = try addShell(
                frame: frame,
                featureID: featureID,
                to: &model,
                generatedNames: &generatedNames
            )
            shellIDs.append(shellID)
        }
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .solid)
        return generatedNames
    }

    private struct CellKey: Hashable, Sendable, Comparable {
        var x: Int
        var y: Int
        var z: Int

        static func < (lhs: CellKey, rhs: CellKey) -> Bool {
            if lhs.x != rhs.x {
                return lhs.x < rhs.x
            }
            if lhs.y != rhs.y {
                return lhs.y < rhs.y
            }
            return lhs.z < rhs.z
        }
    }

    private struct GridVertexKey: Hashable, Sendable, Comparable {
        var x: Int
        var y: Int
        var z: Int

        static func < (lhs: GridVertexKey, rhs: GridVertexKey) -> Bool {
            if lhs.x != rhs.x {
                return lhs.x < rhs.x
            }
            if lhs.y != rhs.y {
                return lhs.y < rhs.y
            }
            return lhs.z < rhs.z
        }
    }

    private struct GridEdgeKey: Hashable, Sendable {
        var first: GridVertexKey
        var second: GridVertexKey

        init(_ first: GridVertexKey, _ second: GridVertexKey) {
            if second < first {
                self.first = second
                self.second = first
            } else {
                self.first = first
                self.second = second
            }
        }
    }

    private struct CellGrid: Sendable {
        var xCoordinates: [Double]
        var yCoordinates: [Double]
        var zCoordinates: [Double]
        var occupied: Set<CellKey>

        func point(for key: GridVertexKey) -> Point3D {
            Point3D(
                x: xCoordinates[key.x],
                y: yCoordinates[key.y],
                z: zCoordinates[key.z]
            )
        }
    }

    private enum CellFaceDirection: String, CaseIterable, Sendable {
        case minZ
        case maxZ
        case minY
        case maxX
        case maxY
        case minX

        var normal: Vector3D {
            switch self {
            case .minZ:
                return -Vector3D.unitZ
            case .maxZ:
                return .unitZ
            case .minY:
                return -Vector3D.unitY
            case .maxX:
                return .unitX
            case .maxY:
                return .unitY
            case .minX:
                return -Vector3D.unitX
            }
        }

        func neighbor(of cell: CellKey) -> CellKey {
            switch self {
            case .minZ:
                return CellKey(x: cell.x, y: cell.y, z: cell.z - 1)
            case .maxZ:
                return CellKey(x: cell.x, y: cell.y, z: cell.z + 1)
            case .minY:
                return CellKey(x: cell.x, y: cell.y - 1, z: cell.z)
            case .maxX:
                return CellKey(x: cell.x + 1, y: cell.y, z: cell.z)
            case .maxY:
                return CellKey(x: cell.x, y: cell.y + 1, z: cell.z)
            case .minX:
                return CellKey(x: cell.x - 1, y: cell.y, z: cell.z)
            }
        }

        func vertices(for cell: CellKey) -> [GridVertexKey] {
            let x0 = cell.x
            let x1 = cell.x + 1
            let y0 = cell.y
            let y1 = cell.y + 1
            let z0 = cell.z
            let z1 = cell.z + 1
            switch self {
            case .minZ:
                return [
                    GridVertexKey(x: x0, y: y0, z: z0),
                    GridVertexKey(x: x0, y: y1, z: z0),
                    GridVertexKey(x: x1, y: y1, z: z0),
                    GridVertexKey(x: x1, y: y0, z: z0),
                ]
            case .maxZ:
                return [
                    GridVertexKey(x: x0, y: y0, z: z1),
                    GridVertexKey(x: x1, y: y0, z: z1),
                    GridVertexKey(x: x1, y: y1, z: z1),
                    GridVertexKey(x: x0, y: y1, z: z1),
                ]
            case .minY:
                return [
                    GridVertexKey(x: x0, y: y0, z: z0),
                    GridVertexKey(x: x1, y: y0, z: z0),
                    GridVertexKey(x: x1, y: y0, z: z1),
                    GridVertexKey(x: x0, y: y0, z: z1),
                ]
            case .maxX:
                return [
                    GridVertexKey(x: x1, y: y0, z: z0),
                    GridVertexKey(x: x1, y: y1, z: z0),
                    GridVertexKey(x: x1, y: y1, z: z1),
                    GridVertexKey(x: x1, y: y0, z: z1),
                ]
            case .maxY:
                return [
                    GridVertexKey(x: x1, y: y1, z: z0),
                    GridVertexKey(x: x0, y: y1, z: z0),
                    GridVertexKey(x: x0, y: y1, z: z1),
                    GridVertexKey(x: x1, y: y1, z: z1),
                ]
            case .minX:
                return [
                    GridVertexKey(x: x0, y: y1, z: z0),
                    GridVertexKey(x: x0, y: y0, z: z0),
                    GridVertexKey(x: x0, y: y0, z: z1),
                    GridVertexKey(x: x0, y: y1, z: z1),
                ]
            }
        }
    }

    private struct CellFaceDescriptor: Sendable {
        var direction: CellFaceDirection
        var vertices: [GridVertexKey]
        var subshape: String

        var edgeKeys: [GridEdgeKey] {
            vertices.indices.map { index in
                let nextIndex = index == vertices.count - 1 ? 0 : index + 1
                return GridEdgeKey(vertices[index], vertices[nextIndex])
            }
        }
    }

    private func addCellUnionShells(
        cells: [AxisAlignedBox],
        featureID: FeatureID,
        to model: inout BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> [ShellID] {
        let grid = try makeCellGrid(from: cells)
        let exposedFaces = exposedCellFaces(in: grid)
        guard exposedFaces.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Cell-union boolean result has no exposed faces.")
        }
        let components = connectedFaceComponents(exposedFaces)
        return try components.enumerated().map { componentIndex, faces in
            try addCellUnionShell(
                componentIndex: componentIndex,
                faces: faces,
                grid: grid,
                featureID: featureID,
                to: &model,
                generatedNames: &generatedNames
            )
        }
    }

    private func makeCellGrid(from cells: [AxisAlignedBox]) throws -> CellGrid {
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult("Cell-union boolean result requires at least one cell.")
        }
        let xCoordinates = uniqueSorted(cells.flatMap { [$0.minimum.x, $0.maximum.x] }, tolerance: tolerance)
        let yCoordinates = uniqueSorted(cells.flatMap { [$0.minimum.y, $0.maximum.y] }, tolerance: tolerance)
        let zCoordinates = uniqueSorted(cells.flatMap { [$0.minimum.z, $0.maximum.z] }, tolerance: tolerance)
        guard xCoordinates.count >= 2, yCoordinates.count >= 2, zCoordinates.count >= 2 else {
            throw FeatureEvaluationError.emptyResult("Cell-union boolean result collapsed to an empty grid.")
        }
        var occupied = Set<CellKey>()
        for cell in cells {
            let minX = try coordinateIndex(cell.minimum.x, in: xCoordinates)
            let maxX = try coordinateIndex(cell.maximum.x, in: xCoordinates)
            let minY = try coordinateIndex(cell.minimum.y, in: yCoordinates)
            let maxY = try coordinateIndex(cell.maximum.y, in: yCoordinates)
            let minZ = try coordinateIndex(cell.minimum.z, in: zCoordinates)
            let maxZ = try coordinateIndex(cell.maximum.z, in: zCoordinates)
            guard minX < maxX, minY < maxY, minZ < maxZ else {
                throw FeatureEvaluationError.emptyResult("Cell-union boolean result contains a collapsed cell.")
            }
            for xIndex in minX..<maxX {
                for yIndex in minY..<maxY {
                    for zIndex in minZ..<maxZ {
                        occupied.insert(CellKey(x: xIndex, y: yIndex, z: zIndex))
                    }
                }
            }
        }
        return CellGrid(
            xCoordinates: xCoordinates,
            yCoordinates: yCoordinates,
            zCoordinates: zCoordinates,
            occupied: occupied
        )
    }

    private func coordinateIndex(_ value: Double, in coordinates: [Double]) throws -> Int {
        for (index, coordinate) in coordinates.enumerated() {
            if abs(value - coordinate) <= tolerance.distance {
                return index
            }
        }
        throw FeatureEvaluationError.invalidGraph("Cell-union coordinate is not present in the boolean grid.")
    }

    private func exposedCellFaces(in grid: CellGrid) -> [CellFaceDescriptor] {
        var faces: [CellFaceDescriptor] = []
        for cell in grid.occupied.sorted() {
            for direction in CellFaceDirection.allCases where grid.occupied.contains(direction.neighbor(of: cell)) == false {
                let vertices = direction.vertices(for: cell)
                faces.append(CellFaceDescriptor(
                    direction: direction,
                    vertices: vertices,
                    subshape: cellUnionFaceSubshape(direction: direction, vertices: vertices, grid: grid)
                ))
            }
        }
        return faces.sorted { $0.subshape < $1.subshape }
    }

    private func connectedFaceComponents(_ faces: [CellFaceDescriptor]) -> [[CellFaceDescriptor]] {
        var edgeToFaceIndices: [GridEdgeKey: [Int]] = [:]
        for (faceIndex, face) in faces.enumerated() {
            for edgeKey in face.edgeKeys {
                edgeToFaceIndices[edgeKey, default: []].append(faceIndex)
            }
        }
        var visited = Array(repeating: false, count: faces.count)
        var components: [[CellFaceDescriptor]] = []
        for faceIndex in faces.indices where visited[faceIndex] == false {
            var stack = [faceIndex]
            var componentIndices: [Int] = []
            visited[faceIndex] = true
            while let current = stack.popLast() {
                componentIndices.append(current)
                for edgeKey in faces[current].edgeKeys {
                    for neighbor in edgeToFaceIndices[edgeKey] ?? [] where visited[neighbor] == false {
                        visited[neighbor] = true
                        stack.append(neighbor)
                    }
                }
            }
            let component = componentIndices.map { faces[$0] }.sorted { $0.subshape < $1.subshape }
            components.append(component)
        }
        return components.sorted { lhs, rhs in
            (lhs.first?.subshape ?? "") < (rhs.first?.subshape ?? "")
        }
    }

    private func addCellUnionShell(
        componentIndex: Int,
        faces: [CellFaceDescriptor],
        grid: CellGrid,
        featureID: FeatureID,
        to model: inout BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> ShellID {
        let shellID = ShellID()
        var vertexIDs: [GridVertexKey: VertexID] = [:]
        var edgeIDs: [GridEdgeKey: EdgeID] = [:]
        var faceIDs: [FaceID] = []
        for face in faces {
            let loopEdges = try orientedCellUnionEdges(
                for: face.vertices,
                componentIndex: componentIndex,
                grid: grid,
                featureID: featureID,
                model: &model,
                vertexIDs: &vertexIDs,
                edgeIDs: &edgeIDs,
                generatedNames: &generatedNames
            )
            let faceID = addFace(
                origin: grid.point(for: face.vertices[0]),
                normal: face.direction.normal,
                loopEdges: loopEdges,
                to: &model
            )
            try recordGeneratedName(
                persistentName(
                    featureID,
                    .sideFace,
                    subshape: cellUnionComponentSubshape(componentIndex, face.subshape)
                ),
                reference: .face(faceID),
                in: &generatedNames
            )
            faceIDs.append(faceID)
        }
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        return shellID
    }

    private func orientedCellUnionEdges(
        for vertices: [GridVertexKey],
        componentIndex: Int,
        grid: CellGrid,
        featureID: FeatureID,
        model: inout BRepModel,
        vertexIDs: inout [GridVertexKey: VertexID],
        edgeIDs: inout [GridEdgeKey: EdgeID],
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> [OrientedEdge] {
        try vertices.indices.map { index in
            let nextIndex = index == vertices.count - 1 ? 0 : index + 1
            return try orientedCellUnionEdge(
                from: vertices[index],
                to: vertices[nextIndex],
                componentIndex: componentIndex,
                grid: grid,
                featureID: featureID,
                model: &model,
                vertexIDs: &vertexIDs,
                edgeIDs: &edgeIDs,
                generatedNames: &generatedNames
            )
        }
    }

    private func orientedCellUnionEdge(
        from start: GridVertexKey,
        to end: GridVertexKey,
        componentIndex: Int,
        grid: CellGrid,
        featureID: FeatureID,
        model: inout BRepModel,
        vertexIDs: inout [GridVertexKey: VertexID],
        edgeIDs: inout [GridEdgeKey: EdgeID],
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> OrientedEdge {
        let edgeKey = GridEdgeKey(start, end)
        if let existingEdgeID = edgeIDs[edgeKey] {
            guard let edge = model.edges[existingEdgeID] else {
                throw TopologyError.missingReference("Missing cell-union edge \(existingEdgeID).")
            }
            let startVertexID = try cellUnionVertexID(
                for: start,
                componentIndex: componentIndex,
                grid: grid,
                featureID: featureID,
                model: &model,
                vertexIDs: &vertexIDs,
                generatedNames: &generatedNames
            )
            if edge.startVertexID == startVertexID {
                return OrientedEdge(edgeID: existingEdgeID, orientation: .forward)
            }
            return OrientedEdge(edgeID: existingEdgeID, orientation: .reversed)
        }

        let startVertexID = try cellUnionVertexID(
            for: start,
            componentIndex: componentIndex,
            grid: grid,
            featureID: featureID,
            model: &model,
            vertexIDs: &vertexIDs,
            generatedNames: &generatedNames
        )
        let endVertexID = try cellUnionVertexID(
            for: end,
            componentIndex: componentIndex,
            grid: grid,
            featureID: featureID,
            model: &model,
            vertexIDs: &vertexIDs,
            generatedNames: &generatedNames
        )
        let edgeID = try addLineEdge(from: startVertexID, to: endVertexID, in: &model)
        edgeIDs[edgeKey] = edgeID
        try recordGeneratedName(
            persistentName(
                featureID,
                .edge,
                subshape: cellUnionEdgeSubshape(componentIndex: componentIndex, edgeKey: edgeKey, grid: grid)
            ),
            reference: .edge(edgeID),
            in: &generatedNames
        )
        return OrientedEdge(edgeID: edgeID, orientation: .forward)
    }

    private func cellUnionVertexID(
        for key: GridVertexKey,
        componentIndex: Int,
        grid: CellGrid,
        featureID: FeatureID,
        model: inout BRepModel,
        vertexIDs: inout [GridVertexKey: VertexID],
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> VertexID {
        if let vertexID = vertexIDs[key] {
            return vertexID
        }
        let vertexID = VertexID()
        model.vertices[vertexID] = Vertex(id: vertexID, point: grid.point(for: key))
        vertexIDs[key] = vertexID
        try recordGeneratedName(
            persistentName(
                featureID,
                .vertex,
                subshape: cellUnionVertexSubshape(componentIndex: componentIndex, key: key, grid: grid)
            ),
            reference: .vertex(vertexID),
            in: &generatedNames
        )
        return vertexID
    }

    private func recordGeneratedName(
        _ name: PersistentName,
        reference: TopologyReference,
        in generatedNames: inout [PersistentName: TopologyReference]
    ) throws {
        guard generatedNames[name] == nil else {
            throw FeatureEvaluationError.invalidGraph("Cell-union boolean generated persistent name collision.")
        }
        generatedNames[name] = reference
    }

    private func addShell(
        frame: ZThroughBoxFrame,
        featureID: FeatureID,
        to model: inout BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> ShellID {
        let shellID = ShellID()
        let outer = frame.outer
        let hole = frame.hole
        let points = [
            Point3D(x: outer.minimum.x, y: outer.minimum.y, z: outer.minimum.z),
            Point3D(x: outer.maximum.x, y: outer.minimum.y, z: outer.minimum.z),
            Point3D(x: outer.maximum.x, y: outer.maximum.y, z: outer.minimum.z),
            Point3D(x: outer.minimum.x, y: outer.maximum.y, z: outer.minimum.z),
            Point3D(x: outer.minimum.x, y: outer.minimum.y, z: outer.maximum.z),
            Point3D(x: outer.maximum.x, y: outer.minimum.y, z: outer.maximum.z),
            Point3D(x: outer.maximum.x, y: outer.maximum.y, z: outer.maximum.z),
            Point3D(x: outer.minimum.x, y: outer.maximum.y, z: outer.maximum.z),
            Point3D(x: hole.minimum.x, y: hole.minimum.y, z: outer.minimum.z),
            Point3D(x: hole.maximum.x, y: hole.minimum.y, z: outer.minimum.z),
            Point3D(x: hole.maximum.x, y: hole.maximum.y, z: outer.minimum.z),
            Point3D(x: hole.minimum.x, y: hole.maximum.y, z: outer.minimum.z),
            Point3D(x: hole.minimum.x, y: hole.minimum.y, z: outer.maximum.z),
            Point3D(x: hole.maximum.x, y: hole.minimum.y, z: outer.maximum.z),
            Point3D(x: hole.maximum.x, y: hole.maximum.y, z: outer.maximum.z),
            Point3D(x: hole.minimum.x, y: hole.maximum.y, z: outer.maximum.z),
        ]
        let vertexIDs = points.enumerated().map { index, point in
            let vertexID = VertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedNames[persistentName(featureID, .vertex, subshape: frameVertexSubshapes[index])] = .vertex(vertexID)
            return vertexID
        }
        let edgeVertexPairs = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7),
            (8, 9), (9, 10), (10, 11), (11, 8),
            (12, 13), (13, 14), (14, 15), (15, 12),
            (8, 12), (9, 13), (10, 14), (11, 15),
        ]
        let edgeIDs = try edgeVertexPairs.enumerated().map { index, pair in
            let edgeID = try addLineEdge(
                from: vertexIDs[pair.0],
                to: vertexIDs[pair.1],
                in: &model
            )
            generatedNames[persistentName(featureID, .edge, subshape: frameEdgeSubshapes[index])] = .edge(edgeID)
            return edgeID
        }
        let faceIDs = [
            addFace(
                origin: points[0],
                normal: -Vector3D.unitZ,
                loops: [
                    loop(edges: [
                        OrientedEdge(edgeID: edgeIDs[3], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[2], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[1], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[0], orientation: .reversed),
                    ], role: .outer),
                    loop(edges: [
                        OrientedEdge(edgeID: edgeIDs[12], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[13], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[14], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[15], orientation: .forward),
                    ], role: .inner),
                ],
                to: &model
            ),
            addFace(
                origin: points[4],
                normal: .unitZ,
                loops: [
                    loop(edges: [
                        OrientedEdge(edgeID: edgeIDs[4], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[5], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[6], orientation: .forward),
                        OrientedEdge(edgeID: edgeIDs[7], orientation: .forward),
                    ], role: .outer),
                    loop(edges: [
                        OrientedEdge(edgeID: edgeIDs[19], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[18], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[17], orientation: .reversed),
                        OrientedEdge(edgeID: edgeIDs[16], orientation: .reversed),
                    ], role: .inner),
                ],
                to: &model
            ),
            addFace(origin: points[0], normal: -Vector3D.unitY, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[0], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[9], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[4], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[8], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[1], normal: .unitX, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[1], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[10], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[5], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[9], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[2], normal: .unitY, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[2], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[11], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[6], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[10], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[3], normal: -Vector3D.unitX, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[3], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[8], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[7], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[11], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[8], normal: .unitY, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[20], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[16], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[21], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[12], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[9], normal: -Vector3D.unitX, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[21], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[17], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[22], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[13], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[10], normal: -Vector3D.unitY, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[22], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[18], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[23], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[14], orientation: .reversed),
            ], to: &model),
            addFace(origin: points[11], normal: .unitX, loopEdges: [
                OrientedEdge(edgeID: edgeIDs[23], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[19], orientation: .forward),
                OrientedEdge(edgeID: edgeIDs[20], orientation: .reversed),
                OrientedEdge(edgeID: edgeIDs[15], orientation: .reversed),
            ], to: &model),
        ]
        for (index, faceID) in faceIDs.enumerated() {
            generatedNames[persistentName(featureID, .sideFace, subshape: frameFaceSubshapes[index])] = .face(faceID)
        }
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        return shellID
    }

    private func addShell(
        box: AxisAlignedBox,
        boxIndex: Int,
        featureID: FeatureID,
        to model: inout BRepModel,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> ShellID {
        let shellID = ShellID()
        let points = [
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
        ]
        let vertexSubshapes = boxVertexSubshapes(boxIndex: boxIndex)
        let edgeSubshapes = boxEdgeSubshapes(boxIndex: boxIndex)
        let faceSubshapes = boxFaceSubshapes(boxIndex: boxIndex)
        let vertexIDs = points.enumerated().map { index, point in
            let vertexID = VertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedNames[persistentName(featureID, .vertex, subshape: vertexSubshapes[index])] = .vertex(vertexID)
            return vertexID
        }
        let edgeVertexPairs = [
            (0, 1), (1, 2), (2, 3), (3, 0),
            (4, 5), (5, 6), (6, 7), (7, 4),
            (0, 4), (1, 5), (2, 6), (3, 7),
        ]
        let edgeIDs = try edgeVertexPairs.enumerated().map { index, pair in
            let edgeID = try addLineEdge(
                from: vertexIDs[pair.0],
                to: vertexIDs[pair.1],
                in: &model
            )
            generatedNames[persistentName(featureID, .edge, subshape: edgeSubshapes[index])] = .edge(edgeID)
            return edgeID
        }
        let faceSpecs: [(normal: Vector3D, origin: Point3D, edges: [OrientedEdge])] = [
            (
                normal: -Vector3D.unitZ,
                origin: points[0],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[3], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[2], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[1], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[0], orientation: .reversed),
                ]
            ),
            (
                normal: .unitZ,
                origin: points[4],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[4], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[5], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[6], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[7], orientation: .forward),
                ]
            ),
            (
                normal: -Vector3D.unitY,
                origin: points[0],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[0], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[9], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[4], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[8], orientation: .reversed),
                ]
            ),
            (
                normal: .unitX,
                origin: points[1],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[1], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[10], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[5], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[9], orientation: .reversed),
                ]
            ),
            (
                normal: .unitY,
                origin: points[2],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[2], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[11], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[6], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[10], orientation: .reversed),
                ]
            ),
            (
                normal: -Vector3D.unitX,
                origin: points[3],
                edges: [
                    OrientedEdge(edgeID: edgeIDs[3], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[8], orientation: .forward),
                    OrientedEdge(edgeID: edgeIDs[7], orientation: .reversed),
                    OrientedEdge(edgeID: edgeIDs[11], orientation: .reversed),
                ]
            ),
        ]
        let faceIDs = faceSpecs.enumerated().map { index, spec in
            let faceID = addFace(
                origin: spec.origin,
                normal: spec.normal,
                loopEdges: spec.edges,
                to: &model
            )
            generatedNames[persistentName(featureID, .sideFace, subshape: faceSubshapes[index])] = .face(faceID)
            return faceID
        }
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        return shellID
    }

    private func addLineEdge(
        from startID: VertexID,
        to endID: VertexID,
        in model: inout BRepModel
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing box vertex.")
        }
        let delta = end - start
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let curveID = CurveID()
        let edgeID = EdgeID()
        model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startID,
            endVertexID: endID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        )
        return edgeID
    }

    private func addFace(
        origin: Point3D,
        normal: Vector3D,
        loopEdges: [OrientedEdge],
        to model: inout BRepModel
    ) -> FaceID {
        addFace(
            origin: origin,
            normal: normal,
            loops: [loop(edges: loopEdges, role: .outer)],
            to: &model
        )
    }

    private func loop(edges: [OrientedEdge], role: LoopRole) -> Loop {
        Loop(id: LoopID(), role: role, edges: edges)
    }

    private func addFace(
        origin: Point3D,
        normal: Vector3D,
        loops: [Loop],
        to model: inout BRepModel
    ) -> FaceID {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        model.geometry.surfaces[surfaceID] = .plane(Plane3D(origin: origin, normal: normal))
        for loop in loops {
            model.loops[loop.id] = loop
        }
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: loops.map(\.id))
        return faceID
    }

    private func persistentName(
        _ featureID: FeatureID,
        _ role: GeneratedSubshapeRole,
        subshape: String? = nil
    ) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let subshape {
            components.append(.subshape(subshape))
        }
        return PersistentName(components: components)
    }

    private func cellUnionComponentSubshape(_ componentIndex: Int, _ localSubshape: String) -> String {
        "cellUnion:component:\(componentIndex):\(localSubshape)"
    }

    private func cellUnionFaceSubshape(
        direction: CellFaceDirection,
        vertices: [GridVertexKey],
        grid: CellGrid
    ) -> String {
        let xIndices = vertices.map(\.x)
        let yIndices = vertices.map(\.y)
        let zIndices = vertices.map(\.z)
        let minX = xIndices.min() ?? 0
        let maxX = xIndices.max() ?? minX
        let minY = yIndices.min() ?? 0
        let maxY = yIndices.max() ?? minY
        let minZ = zIndices.min() ?? 0
        let maxZ = zIndices.max() ?? minZ
        return [
            "face",
            direction.rawValue,
            "x",
            coordinateRangeLabel(axis: "x", lower: minX, upper: maxX, grid: grid),
            "y",
            coordinateRangeLabel(axis: "y", lower: minY, upper: maxY, grid: grid),
            "z",
            coordinateRangeLabel(axis: "z", lower: minZ, upper: maxZ, grid: grid),
        ].joined(separator: ":")
    }

    private func cellUnionVertexSubshape(
        componentIndex: Int,
        key: GridVertexKey,
        grid: CellGrid
    ) -> String {
        [
            "cellUnion",
            "component",
            "\(componentIndex)",
            "vertex",
            "x",
            coordinateLabel(axis: "x", index: key.x, grid: grid),
            "y",
            coordinateLabel(axis: "y", index: key.y, grid: grid),
            "z",
            coordinateLabel(axis: "z", index: key.z, grid: grid),
        ].joined(separator: ":")
    }

    private func cellUnionEdgeSubshape(
        componentIndex: Int,
        edgeKey: GridEdgeKey,
        grid: CellGrid
    ) -> String {
        let first = edgeKey.first
        let second = edgeKey.second
        if first.x != second.x {
            return [
                "cellUnion",
                "component",
                "\(componentIndex)",
                "xEdge",
                "x",
                coordinateRangeLabel(axis: "x", lower: first.x, upper: second.x, grid: grid),
                "y",
                coordinateLabel(axis: "y", index: first.y, grid: grid),
                "z",
                coordinateLabel(axis: "z", index: first.z, grid: grid),
            ].joined(separator: ":")
        }
        if first.y != second.y {
            return [
                "cellUnion",
                "component",
                "\(componentIndex)",
                "yEdge",
                "x",
                coordinateLabel(axis: "x", index: first.x, grid: grid),
                "y",
                coordinateRangeLabel(axis: "y", lower: first.y, upper: second.y, grid: grid),
                "z",
                coordinateLabel(axis: "z", index: first.z, grid: grid),
            ].joined(separator: ":")
        }
        return [
            "cellUnion",
            "component",
            "\(componentIndex)",
            "zEdge",
            "x",
            coordinateLabel(axis: "x", index: first.x, grid: grid),
            "y",
            coordinateLabel(axis: "y", index: first.y, grid: grid),
            "z",
            coordinateRangeLabel(axis: "z", lower: first.z, upper: second.z, grid: grid),
        ].joined(separator: ":")
    }

    private func coordinateRangeLabel(axis: String, lower: Int, upper: Int, grid: CellGrid) -> String {
        let lowerLabel = coordinateLabel(axis: axis, index: lower, grid: grid)
        let upperLabel = coordinateLabel(axis: axis, index: upper, grid: grid)
        if lowerLabel == upperLabel {
            return lowerLabel
        }
        return "\(lowerLabel)-\(upperLabel)"
    }

    private func coordinateLabel(axis: String, index: Int, grid: CellGrid) -> String {
        let count: Int
        switch axis {
        case "x":
            count = grid.xCoordinates.count
        case "y":
            count = grid.yCoordinates.count
        default:
            count = grid.zCoordinates.count
        }
        if index == 0 {
            return "min\(axis.uppercased())"
        }
        if index == count - 1 {
            return "max\(axis.uppercased())"
        }
        return "\(axis)\(index)"
    }

    private func boxVertexSubshapes(boxIndex: Int) -> [String] {
        [
            "box:\(boxIndex):corner:minX:minY:minZ",
            "box:\(boxIndex):corner:maxX:minY:minZ",
            "box:\(boxIndex):corner:maxX:maxY:minZ",
            "box:\(boxIndex):corner:minX:maxY:minZ",
            "box:\(boxIndex):corner:minX:minY:maxZ",
            "box:\(boxIndex):corner:maxX:minY:maxZ",
            "box:\(boxIndex):corner:maxX:maxY:maxZ",
            "box:\(boxIndex):corner:minX:maxY:maxZ",
        ]
    }

    private func boxEdgeSubshapes(boxIndex: Int) -> [String] {
        [
            "box:\(boxIndex):xEdge:y:minY:z:minZ",
            "box:\(boxIndex):yEdge:x:maxX:z:minZ",
            "box:\(boxIndex):xEdge:y:maxY:z:minZ",
            "box:\(boxIndex):yEdge:x:minX:z:minZ",
            "box:\(boxIndex):xEdge:y:minY:z:maxZ",
            "box:\(boxIndex):yEdge:x:maxX:z:maxZ",
            "box:\(boxIndex):xEdge:y:maxY:z:maxZ",
            "box:\(boxIndex):yEdge:x:minX:z:maxZ",
            "box:\(boxIndex):zEdge:x:minX:y:minY",
            "box:\(boxIndex):zEdge:x:maxX:y:minY",
            "box:\(boxIndex):zEdge:x:maxX:y:maxY",
            "box:\(boxIndex):zEdge:x:minX:y:maxY",
        ]
    }

    private func boxFaceSubshapes(boxIndex: Int) -> [String] {
        [
            "box:\(boxIndex):face:minZ",
            "box:\(boxIndex):face:maxZ",
            "box:\(boxIndex):face:minY",
            "box:\(boxIndex):face:maxX",
            "box:\(boxIndex):face:maxY",
            "box:\(boxIndex):face:minX",
        ]
    }

    private var frameVertexSubshapes: [String] {
        [
            "frame:outer:corner:minX:minY:minZ",
            "frame:outer:corner:maxX:minY:minZ",
            "frame:outer:corner:maxX:maxY:minZ",
            "frame:outer:corner:minX:maxY:minZ",
            "frame:outer:corner:minX:minY:maxZ",
            "frame:outer:corner:maxX:minY:maxZ",
            "frame:outer:corner:maxX:maxY:maxZ",
            "frame:outer:corner:minX:maxY:maxZ",
            "frame:hole:corner:minX:minY:minZ",
            "frame:hole:corner:maxX:minY:minZ",
            "frame:hole:corner:maxX:maxY:minZ",
            "frame:hole:corner:minX:maxY:minZ",
            "frame:hole:corner:minX:minY:maxZ",
            "frame:hole:corner:maxX:minY:maxZ",
            "frame:hole:corner:maxX:maxY:maxZ",
            "frame:hole:corner:minX:maxY:maxZ",
        ]
    }

    private var frameEdgeSubshapes: [String] {
        [
            "frame:outer:xEdge:y:minY:z:minZ",
            "frame:outer:yEdge:x:maxX:z:minZ",
            "frame:outer:xEdge:y:maxY:z:minZ",
            "frame:outer:yEdge:x:minX:z:minZ",
            "frame:outer:xEdge:y:minY:z:maxZ",
            "frame:outer:yEdge:x:maxX:z:maxZ",
            "frame:outer:xEdge:y:maxY:z:maxZ",
            "frame:outer:yEdge:x:minX:z:maxZ",
            "frame:outer:zEdge:x:minX:y:minY",
            "frame:outer:zEdge:x:maxX:y:minY",
            "frame:outer:zEdge:x:maxX:y:maxY",
            "frame:outer:zEdge:x:minX:y:maxY",
            "frame:hole:xEdge:y:minY:z:minZ",
            "frame:hole:yEdge:x:maxX:z:minZ",
            "frame:hole:xEdge:y:maxY:z:minZ",
            "frame:hole:yEdge:x:minX:z:minZ",
            "frame:hole:xEdge:y:minY:z:maxZ",
            "frame:hole:yEdge:x:maxX:z:maxZ",
            "frame:hole:xEdge:y:maxY:z:maxZ",
            "frame:hole:yEdge:x:minX:z:maxZ",
            "frame:hole:zEdge:x:minX:y:minY",
            "frame:hole:zEdge:x:maxX:y:minY",
            "frame:hole:zEdge:x:maxX:y:maxY",
            "frame:hole:zEdge:x:minX:y:maxY",
        ]
    }

    private var frameFaceSubshapes: [String] {
        [
            "frame:face:minZ",
            "frame:face:maxZ",
            "frame:outerFace:minY",
            "frame:outerFace:maxX",
            "frame:outerFace:maxY",
            "frame:outerFace:minX",
            "frame:holeFace:minY",
            "frame:holeFace:maxX",
            "frame:holeFace:maxY",
            "frame:holeFace:minX",
        ]
    }
}

func uniqueSorted(_ values: [Double], tolerance: ModelingTolerance) -> [Double] {
    let sorted = values.sorted()
    var result: [Double] = []
    for value in sorted {
        guard let last = result.last else {
            result.append(value)
            continue
        }
        if abs(value - last) > tolerance.distance {
            result.append(value)
        }
    }
    return result
}
