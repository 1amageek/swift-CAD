import CADCore
import CADGeometry

/// Searches for positive material evidence; an unsuccessful search proves no absence.
struct OriginalContainmentMaterialWitness: Sendable {
    private struct Cell {
        let bounds: BoundingBox3D
        let depth: Int
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Q1 containment/identical-body witness
    // search accepts only both-inside classifications of the identical candidate.
    // Classifier lower BYTES and combined search/source-depth admission remain
    // required before this route can establish whole-query resource completion.
    func witness(in pair: PreparedSolidClassificationPair,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> Point3D? {
        let tolerance = pair.validatedModel.tolerance
        let admission = try OriginalSolidClassificationAdmission(
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, tolerance: tolerance)
        try admission.consume()
        guard let first = try pair.firstClassification.originalSpatialBounds(),
              let second = try pair.secondClassification.originalSpatialBounds() else {
            throw KernelError(phase: .classification, code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The injected original material sessions expose no retained spatial-bound receipt.")
        }
        let low = Point3D(x: max(first.minimum.x, second.minimum.x),
            y: max(first.minimum.y, second.minimum.y), z: max(first.minimum.z, second.minimum.z))
        let high = Point3D(x: min(first.maximum.x, second.maximum.x),
            y: min(first.maximum.y, second.maximum.y), z: min(first.maximum.z, second.maximum.z))
        guard low.x < high.x, low.y < high.y, low.z < high.z else { return nil }
        let capacity = maximumSubdivisionDepth + 1
        let bytes = capacity.multipliedReportingOverflow(by: MemoryLayout<Cell>.stride)
        guard !bytes.overflow else {
            throw KernelError(phase: .classification, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original material candidate storage overflowed.")
        }
        try admission.consume()
        try consumeStorage?(bytes.partialValue)
        var frontier: [Cell] = []
        frontier.reserveCapacity(capacity)
        frontier.append(Cell(bounds: try BoundingBox3D(minimum: low, maximum: high), depth: 0))
        while let cell = frontier.popLast() {
            try admission.consume(cell.depth)
            let a = cell.bounds.minimum, b = cell.bounds.maximum
            let candidate = Point3D(x: a.x * 0.5 + b.x * 0.5,
                y: a.y * 0.5 + b.y * 0.5, z: a.z * 0.5 + b.z * 0.5)
            try candidate.validate()
            if try pair.firstClassification.classify(candidate) == .inside,
               try pair.secondClassification.classify(candidate) == .inside {
                try Task.checkCancellation()
                return candidate
            }
            guard cell.depth < maximumSubdivisionDepth else { continue }
            let x = b.x * 0.5 - a.x * 0.5
            let y = b.y * 0.5 - a.y * 0.5
            let z = b.z * 0.5 - a.z * 0.5
            let axis = x >= y && x >= z ? 0 : (y >= z ? 1 : 2)
            var firstHigh = b, secondLow = a
            switch axis {
            case 0:
                guard a.x < candidate.x, candidate.x < b.x else { continue }
                firstHigh = Point3D(x: candidate.x, y: b.y, z: b.z)
                secondLow = Point3D(x: candidate.x, y: a.y, z: a.z)
            case 1:
                guard a.y < candidate.y, candidate.y < b.y else { continue }
                firstHigh = Point3D(x: b.x, y: candidate.y, z: b.z)
                secondLow = Point3D(x: a.x, y: candidate.y, z: a.z)
            default:
                guard a.z < candidate.z, candidate.z < b.z else { continue }
                firstHigh = Point3D(x: b.x, y: b.y, z: candidate.z)
                secondLow = Point3D(x: a.x, y: a.y, z: candidate.z)
            }
            try admission.consume(cell.depth)
            guard frontier.count + 2 <= capacity else {
                throw KernelError(phase: .classification, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original material DFS exceeded its admitted depth frontier.")
            }
            frontier.append(Cell(bounds: try BoundingBox3D(minimum: secondLow, maximum: b), depth: cell.depth + 1))
            frontier.append(Cell(bounds: try BoundingBox3D(minimum: a, maximum: firstHigh), depth: cell.depth + 1))
        }
        try Task.checkCancellation()
        return nil
    }
}
