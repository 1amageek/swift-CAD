import HashTreeCollections
import CADCore
import CADGeometry

/// Audits staged actions against the immutable task-original source.
struct BRepRepairAudit {
    func describe<Tag>(_ identifier: TaggedID<Tag>, using execution: inout OriginalQueryExecution) throws -> String {
        // Core's canonical formatter owns the fixed raw, UTF-8 scratch and String payloads.
        try execution.retainStorage(bytes: 16 + 36 + 36)
        try execution.consumeWork(16)
        return identifier.description
    }

    func identifier<Tag>(_ identifier: TaggedID<Tag>, kind: String,
        using execution: inout OriginalQueryExecution) throws -> String {
        let canonical = try describe(identifier, using: &execution)
        return try composed(prefix: kind, value: ":", suffix: canonical, using: &execution)
    }

    func composed(prefix: String, value: String, suffix: String = "",
        using execution: inout OriginalQueryExecution) throws -> String {
        let head = prefix.utf8.count.addingReportingOverflow(value.utf8.count)
        let total = head.partialValue.addingReportingOverflow(suffix.utf8.count)
        guard !head.overflow, !total.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: total.partialValue)
        try execution.consumeWork(total.partialValue)
        var result = String()
        result.reserveCapacity(total.partialValue)
        result.append(prefix); result.append(value); result.append(suffix)
        return result
    }

    func text(_ value: String, using execution: inout OriginalQueryExecution) throws -> String {
        try composed(prefix: "", value: value, using: &execution)
    }

    func maximumDisplacement(from original: BRepModel, to candidate: BRepModel,
        collapsedCurves: [BRepRepairCollapsedCurve],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        var maximum = 0.0
        for (id, edge) in original.edges {
            try execution.consumeWork(1)
            guard let repaired = candidate.edges[id] else { continue }
            try execution.retainStorage(bytes: 2 * MemoryLayout<(VertexID, VertexID)>.stride)
            for (oldID, newID) in [(edge.startVertexID, repaired.startVertexID),
                                  (edge.endVertexID, repaired.endVertexID)] {
                try execution.consumeWork(1)
                guard let old = original.vertices[oldID], let new = candidate.vertices[newID] else {
                    // Missing references remain owned by final scoped validation.
                    continue
                }
                let displacement = distanceUpperBound(old.point,new.point)
                guard displacement.isFinite else {
                    throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                        message: "Repair displacement arithmetic is nonfinite.")
                }
                maximum = max(maximum, displacement)
            }
        }
        for collapsed in collapsedCurves {
            try execution.consumeWork(1)
            guard let point = candidate.vertices[collapsed.retainedVertexID]?.point else {
                return .infinity
            }
            let originalPosition = try DefaultCurveDifferentialEncloser().enclosure(of: collapsed.curve,
                over: collapsed.interval, tolerance: tolerance, using: &execution).position
            func axis(_ interval: ScalarInterval, _ value: Double) -> Double {
                max(abs((interval.lower-value).nextDown), abs((interval.upper-value).nextUp))
            }
            let x = axis(originalPosition.x, point.x), y = axis(originalPosition.y, point.y)
            let z = axis(originalPosition.z, point.z)
            let bound = magnitudeUpperBound(x,y,z)
            guard bound.isFinite else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                    message: "Original collapsed curve displacement arithmetic is nonfinite.")
            }
            maximum = max(maximum, bound)
        }
        return maximum
    }

    func stationDisplacementUpperBound(of curve: Curve3D, at parameter: Double,
        from point: Point3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        let limits = execution.effectiveLimits
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve,
            tolerance: tolerance, remainingSourceDepth: limits.remainingSourceDepth,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: 32, using: &execution)
        let position = try prepared.positionBounds(over: ScalarInterval(lower: parameter, upper: parameter),
            tolerance: tolerance, maximumSpanCount: limits.maximumSpans,
            maximumSubdivisionDepth: limits.maximumSubdivisionDepth,
            remainingSourceDepth: limits.remainingSourceDepth, using: &execution)
        func axis(_ interval: OutwardScalarInterval, _ coordinate: Double) -> Double {
            max(abs((interval.lower - coordinate).nextDown),
                abs((interval.upper - coordinate).nextUp))
        }
        return magnitudeUpperBound(axis(position.x, point.x), axis(position.y, point.y),
            axis(position.z, point.z))
    }

    func distanceUpperBound(_ first: Point3D,_ second: Point3D) -> Double {
        if first == second { return 0 }
        func magnitude(_ a: Double,_ b: Double) -> Double {
            let d = a-b
            return max(abs(d.nextDown),abs(d.nextUp))
        }
        let x = magnitude(first.x,second.x),y = magnitude(first.y,second.y),z = magnitude(first.z,second.z)
        return magnitudeUpperBound(x,y,z)
    }

    func magnitudeUpperBound(_ x: Double,_ y: Double,_ z: Double) -> Double {
        OriginalDistanceMagnitude.bounds(x,y,z).upper
    }

    func entityDelta(from original: BRepModel, to candidate: BRepModel,
        using execution: inout OriginalQueryExecution) throws
        -> (affected: [String], generated: [String], deleted: [String]) {
        func identifiers(_ model: BRepModel, using execution: inout OriginalQueryExecution) throws -> Set<String> {
            var ids = Set<String>()
            func insert<Tag>(_ kind: String, _ keys: some Sequence<TaggedID<Tag>>,
                using execution: inout OriginalQueryExecution) throws {
                for key in keys {
                    let text = try BRepRepairAudit().identifier(key, kind: kind, using: &execution)
                    try execution.consumeWork(text.utf8.count)
                    try OriginalParameterQueryStorage.insert(text, in: &ids, using: &execution)
                }
            }
            try insert("body", model.bodies.keys, using: &execution)
            try insert("shell", model.shells.keys, using: &execution)
            try insert("face", model.faces.keys, using: &execution)
            try insert("loop", model.loops.keys, using: &execution)
            try insert("edge", model.edges.keys, using: &execution)
            try insert("vertex", model.vertices.keys, using: &execution)
            try insert("curve", model.geometry.curves.keys, using: &execution)
            try insert("surface", model.geometry.surfaces.keys, using: &execution)
            return ids
        }
        let before = try identifiers(original, using: &execution)
        let after = try identifiers(candidate, using: &execution)
        var generated = Set<String>(), deleted = Set<String>(), affected = Set<String>()
        for id in after {
            try execution.consumeWork(1)
            try execution.consumeWork(id.utf8.count)
            if !before.contains(id) {
                try execution.consumeWork(id.utf8.count)
                try OriginalParameterQueryStorage.insert(id, in: &generated, using: &execution)
                try execution.consumeWork(id.utf8.count)
                try OriginalParameterQueryStorage.insert(id, in: &affected, using: &execution)
            }
        }
        for id in before {
            try execution.consumeWork(1)
            try execution.consumeWork(id.utf8.count)
            if !after.contains(id) {
                try execution.consumeWork(id.utf8.count)
                try OriginalParameterQueryStorage.insert(id, in: &deleted, using: &execution)
                try execution.consumeWork(id.utf8.count)
                try OriginalParameterQueryStorage.insert(id, in: &affected, using: &execution)
            }
        }
        try OriginalBRepStructuralComparison.charge(original, using: &execution)
        try OriginalBRepStructuralComparison.charge(candidate, using: &execution)
        func changed<Tag, Value: Equatable>(_ kind: String,
            _ before: PersistentMap<TaggedID<Tag>, Value>, _ after: PersistentMap<TaggedID<Tag>, Value>,
            using execution: inout OriginalQueryExecution) throws {
            for (id, value) in after {
                try execution.consumeWork(1)
                guard before[id] != value else { continue }
                let text = try BRepRepairAudit().identifier(id, kind: kind, using: &execution)
                try execution.consumeWork(text.utf8.count)
                try OriginalParameterQueryStorage.insert(text, in: &affected, using: &execution)
            }
        }
        try changed("body", original.bodies, candidate.bodies, using: &execution)
        try changed("shell", original.shells, candidate.shells, using: &execution)
        try changed("face", original.faces, candidate.faces, using: &execution)
        try changed("loop", original.loops, candidate.loops, using: &execution)
        try changed("edge", original.edges, candidate.edges, using: &execution)
        try changed("vertex", original.vertices, candidate.vertices, using: &execution)
        try changed("curve", original.geometry.curves, candidate.geometry.curves, using: &execution)
        try changed("surface", original.geometry.surfaces, candidate.geometry.surfaces, using: &execution)
        func ordered(_ values: Set<String>, using execution: inout OriginalQueryExecution) throws -> [String] {
            var result = try OriginalParameterQueryStorage.materialize(values, using: &execution)
            try OriginalParameterQueryStorage.sort(&result, using: &execution) { first, second, execution in
                try execution.consumeWork(first.utf8.count)
                try execution.consumeWork(second.utf8.count)
                return first < second
            }
            return result
        }
        return (try ordered(affected, using: &execution), try ordered(generated, using: &execution),
            try ordered(deleted, using: &execution))
    }
}
