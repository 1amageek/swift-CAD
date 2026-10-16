import CADCore
import CADGeometry
import CADTopology

extension OriginalQueryExecution {
    mutating func visitDrawingSource(depth: Int) throws {
        try admitSourceDepth(depth)
        try consumeWork(1)
    }
    mutating func visitDrawingCell(depth: Int) throws {
        try admitGeometricDepth(depth)
        try consumeCells(1)
        try consumeWork(1)
    }
}

/// Mutates grouped query-local storage without copying each retained bucket.
enum BRepDrawingGroupedStorage {
    static func append<Key: Hashable, Value>(_ value: Value, for key: Key,
        in groups: inout [Key: [Value]], using execution: inout OriginalQueryExecution) throws {
        if groups[key] == nil {
            try OriginalParameterQueryStorage.set([], for: key, in: &groups, using: &execution)
        }
        try OriginalParameterQueryStorage.append(value, to: &groups[key]!, using: &execution)
    }

    static func insert<Key: Hashable, Value: Hashable>(_ value: Value, for key: Key,
        in groups: inout [Key: Set<Value>], using execution: inout OriginalQueryExecution) throws {
        if groups[key] == nil {
            try OriginalParameterQueryStorage.set([], for: key, in: &groups, using: &execution)
        }
        try OriginalParameterQueryStorage.insert(value, in: &groups[key]!, using: &execution)
    }
}

/// Charges the retained variable payloads used by authored occurrence equality.
enum BRepDrawingPlacementComparison {
    static func equal(_ first: BRepDrawingPlacement?, _ second: BRepDrawingPlacement?,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        for ordinal in 0..<2 {
            try execution.consumeWork(1)
            guard let placement = ordinal == 0 ? first : second else { continue }
            try execution.consumeWork(placement.identity.utf8.count)
            if let word = placement.operationWord {
                try GeometryStructuralComparisonWork.charge(word: word, using: &execution)
            }
        }
        return first == second
    }
}
