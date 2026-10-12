import HashTreeCollections
import CADCore
import CADGeometry

/// Audits staged actions against the immutable task-original source.
struct BRepRepairAudit {
    func maximumDisplacement(from original: BRepModel, to candidate: BRepModel,
        collapsedCurves: [BRepRepairCollapsedCurve],
        tolerance: ModelingTolerance) throws -> Double {
        var maximum = 0.0
        for (id, edge) in original.edges {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let repaired = candidate.edges[id] else { continue }
            for (oldID, newID) in [(edge.startVertexID, repaired.startVertexID),
                                  (edge.endVertexID, repaired.endVertexID)] {
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
            try CurrentTaskCancellationChecker().checkCancellation()
            guard let point = candidate.vertices[collapsed.retainedVertexID]?.point else {
                return .infinity
            }
            let originalPosition = try DefaultCurveDifferentialEncloser().enclosure(of: collapsed.curve,
                over: collapsed.interval, tolerance: tolerance).position
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
        from point: Point3D, tolerance: ModelingTolerance) throws -> Double {
        let position = try DefaultCurveDifferentialEncloser().enclosure(of: curve,
            over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance).position
        func axis(_ interval: ScalarInterval, _ coordinate: Double) -> Double {
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

    func entityDelta(from original: BRepModel, to candidate: BRepModel)
        -> (affected: [String], generated: [String], deleted: [String]) {
        func identifiers(_ model: BRepModel) -> Set<String> {
            var ids = Set<String>()
            func insert<Key: CustomStringConvertible>(_ kind: String, _ keys: some Sequence<Key>) {
                for key in keys { ids.insert(kind+":"+key.description) }
            }
            insert("body", model.bodies.keys)
            insert("shell", model.shells.keys)
            insert("face", model.faces.keys)
            insert("loop", model.loops.keys)
            insert("edge", model.edges.keys)
            insert("vertex", model.vertices.keys)
            insert("curve", model.geometry.curves.keys)
            insert("surface", model.geometry.surfaces.keys)
            return ids
        }
        let before = identifiers(original), after = identifiers(candidate)
        let generated = after.subtracting(before), deleted = before.subtracting(after)
        var affected = generated.union(deleted)
        func changed<Key: Hashable & CustomStringConvertible, Value: Equatable>(_ kind: String,
            _ before: PersistentMap<Key, Value>, _ after: PersistentMap<Key, Value>) {
            for (id, value) in after where before[id] != value {
                affected.insert(kind + ":" + id.description)
            }
        }
        changed("body", original.bodies, candidate.bodies)
        changed("shell", original.shells, candidate.shells)
        changed("face", original.faces, candidate.faces)
        changed("loop", original.loops, candidate.loops)
        changed("edge", original.edges, candidate.edges)
        changed("vertex", original.vertices, candidate.vertices)
        changed("curve", original.geometry.curves, candidate.geometry.curves)
        changed("surface", original.geometry.surfaces, candidate.geometry.surfaces)
        return (affected.sorted(), generated.sorted(), deleted.sorted())
    }
}
