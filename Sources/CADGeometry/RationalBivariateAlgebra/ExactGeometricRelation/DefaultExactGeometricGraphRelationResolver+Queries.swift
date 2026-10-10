#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricGraphRelationResolver {
    func stationPredicate<A: ExactScalarAdmission & ~Copyable>(_ station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricGraphRelation<Base>, _ a: inout A) throws -> (Cells, ExactRealCellPredicate<Base>, Bool) {
        let station = copy station, original = relation.original.original
        try a.checkpoint(); try a.admitDepth(value: relation.depth.value, coefficient: relation.depth.coefficient)
        let field: Field
        switch station {
        case .xyz(let p): field = p.field
        case .curveParameter(let f, _): field = f
        case .firstSurfaceUV(let p), .secondSurfaceUV(let p): field = p.field
        }
        let raw = try Cells(retaining: original.predicate.source, using: &a)
        let retained = try raw.coefficientField(of: original.predicate.source, using: &a)
        _ = try field.importing(retained.integer(0, using: &a), using: &a)
        let firstPosition = try parameterPosition(original.first, &a)
        let secondPosition = try parameterPosition(original.second, &a)
        let parameterOnly: Bool
        if case .xyz = station { parameterOnly = firstPosition || secondPosition } else { parameterOnly = true }
        let base = parameterOnly ? relation.original.selection.predicate : original.predicate
        let anchor = !firstPosition && secondPosition ? original.second : original.first
        let placement = !firstPosition && secondPosition ? original.secondCoordinates : original.firstCoordinates
        let cells = try Cells(field: field, variableCount: base.source.variableCount, using: &a), ring = cells.polynomials
        let capacity = try ExactGeometryAccess.add(base.source.polynomials.count, 3)
        try ExactGeometryAccess.storage(capacity, Polynomial.self, &a)
        var laws: [Polynomial] = []; laws.reserveCapacity(capacity)
        for law in base.source.polynomials { laws.append(try ring.importing(law, using: &a)) }
        let start = laws.count
        switch station {
        case .xyz(let point):
            let position = anchor.predicate.source.polynomials
            let weight = try remap(position[3], placement: placement, into: ring, field: field, &a)
            for axis in 0..<3 {
                let value = try field.importing(axis == 0 ? point.x : axis == 1 ? point.y : point.z, using: &a)
                let h = try remap(position[axis], placement: placement, into: ring, field: field, &a)
                laws.append(try ring.subtracting(ring.multiplying(ring.constant(value, using: &a), weight, using: &a), h, using: &a))
            }
        case .curveParameter(_, let input):
            guard original.kind == .curveSurface else { throw ExactGeometricRelationFailure.invalidStation }
            laws.append(try ring.subtracting(ring.variable(0, using: &a), ring.constant(field.importing(input, using: &a), using: &a), using: &a))
        case .firstSurfaceUV(let uv), .secondSurfaceUV(let uv):
            let offset: Int
            if case .firstSurfaceUV = station {
                guard original.kind == .surfaceSurface else { throw ExactGeometricRelationFailure.invalidStation }
                offset = 0
            } else { offset = original.first.parameterCount }
            let u = try field.importing(uv.u, using: &a), v = try field.importing(uv.v, using: &a)
            laws.append(try ring.subtracting(ring.variable(offset, using: &a), ring.constant(u, using: &a), using: &a))
            laws.append(try ring.subtracting(ring.variable(offset + 1, using: &a), ring.constant(v, using: &a), using: &a))
        }
        let source = try cells.bind(polynomials: laws, domains: base.source.domains, using: &a)
        let count = try ExactGeometryAccess.add(base.instructions.count, try ExactGeometryAccess.multiply(laws.count - start, 2))
        try ExactGeometryAccess.storage(count, ExactRealCellInstruction.self, &a)
        var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(count)
        for instruction in base.instructions { try a.consumeWork(1); instructions.append(instruction) }
        for i in start..<laws.count { instructions.append(.sign(polynomial: i, relation: .equal)); instructions.append(.and) }
        return (cells, try cells.predicate(instructions: instructions, for: source, using: &a), parameterOnly)
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactXYZ<Base>,
        in relation: borrowing ExactGeometricGraphRelation<Base>, limits: ExactGeometricRelationLimits, using a: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool {
        do {
            let (cells, predicate, _) = try stationPredicate(.xyz(copy point), in: relation, &a)
            let partition = try cells.decompose(predicate.source, limits: limits.cells, using: &a)
            let selection = try cells.select(partition, matching: predicate, using: &a)
            try a.checkpoint(); return !selection.cells.isEmpty
        } catch { throw .preserving(error) }
    }
    public func fiber<A: ExactScalarAdmission & ~Copyable>(at station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricGraphRelation<Base>, limits: ExactGeometricRelationLimits, using a: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphFiber<Base> {
        do {
            let (cells, predicate, parameterOnly) = try stationPredicate(station, in: relation, &a)
            let partition = try cells.decompose(predicate.source, limits: limits.cells, using: &a)
            let selection = try cells.select(partition, matching: predicate, using: &a)
            let projection = try Topology(cells: Cells.self).project(selection, retainingPrefix: relation.original.original.parameterCount,
                cellLimits: limits.cells, topologyLimits: limits.topology, using: &a)
            try ExactGeometryAccess.storage(1, ExactGeometricGraphFiber<Base>.self, &a)
            let result = ExactGeometricGraphFiber(parent: copy relation, station: copy station, projection: projection, usesParameterProjection: parameterOnly)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
    public func containsLift<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactRealCellSample<Base>,
        in fiber: borrowing ExactGeometricGraphFiber<Base>, limits: ExactGeometricRelationLimits, using a: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool {
        do {
            try a.checkpoint(); try a.admitDepth(value: fiber.parent.depth.value, coefficient: fiber.parent.depth.coefficient)
            try a.admitDepth(value: fiber.projection.depth.value, coefficient: fiber.projection.depth.coefficient)
            let parameterOnly = fiber.usesParameterProjection
            let original = parameterOnly ? fiber.sourceProjection.original : fiber.projection.original
            guard point.coordinates.count == original.partition.source.variableCount else { throw ExactGeometricRelationFailure.invalidStation }
            let cells = try Cells(retaining: original.partition.source, using: &a)
            let roots = try ExactRealRootLimits(maximumRoots: limits.cells.maximumRootsPerStack)
            var accepted = false
            if let cell = try cells.locate(point, in: original.partition, limits: roots, using: &a) {
                for candidate in original.cells { try a.consumeWork(1); if candidate == cell { accepted = true; break } }
            }
            if accepted && parameterOnly {
                let count = fiber.parent.original.original.parameterCount
                let selected = fiber.selection
                let query = try Cells(retaining: selected.partition.source, using: &a)
                let coefficientField = try query.coefficientField(of: selected.partition.source, using: &a)
                // The station may retain a child field of the original lift's field.
                // Import into the deeper field; unrelated owners remain an explicit failure.
                let field = coefficientField.extensionLevel > point.field.extensionLevel ? coefficientField : point.field
                try ExactGeometryAccess.storage(count, Field.Value.self, &a)
                var coordinates: [Field.Value] = []; coordinates.reserveCapacity(count)
                for i in 0..<count { try a.consumeWork(1); coordinates.append(try field.importing(point.coordinates[i], using: &a)) }
                let parameterPoint = try query.point(field: field, coordinates: coordinates, using: &a)
                accepted = false
                if let cell = try query.locate(parameterPoint, in: selected.partition, limits: roots, using: &a) {
                    for candidate in selected.cells { try a.consumeWork(1); if candidate == cell { accepted = true; break } }
                }
            }
            try a.checkpoint(); return accepted
        } catch { throw .preserving(error) }
    }

}
