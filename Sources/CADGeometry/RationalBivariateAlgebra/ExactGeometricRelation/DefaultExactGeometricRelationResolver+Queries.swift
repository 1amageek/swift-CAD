#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricRelationResolver: ExactGeometricRelationQuerying {
    func stationPredicate<A: ExactScalarAdmission & ~Copyable>(_ station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricRelation<Base>, _ a: inout A) throws -> (Cells, ExactRealCellPredicate<Base>) {
        let station = copy station
        try a.checkpoint(); try a.admitDepth(value: relation.depth.value, coefficient: relation.depth.coefficient)
        let original = relation.original.original, field: Field
        switch station {
        case .xyz(let p): field = p.field
        case .curveParameter(let f, _): field = f
        case .firstSurfaceUV(let p), .secondSurfaceUV(let p): field = p.field
        }
        let raw = try Cells(retaining: original.predicate.source, using: &a)
        let sourceField = try raw.coefficientField(of: original.predicate.source, using: &a)
        _ = try field.importing(sourceField.integer(0, using: &a), using: &a)
        let cells = try Cells(field: field, variableCount: original.predicate.source.variableCount, using: &a), p = cells.polynomials
        let capacity = try ExactGeometryAccess.add(original.predicate.source.polynomials.count, 3)
        try ExactGeometryAccess.storage(capacity, Polynomial.self, &a)
        var laws: [Polynomial] = []; laws.reserveCapacity(capacity)
        for law in original.predicate.source.polynomials { try a.consumeWork(1); laws.append(try p.importing(law, using: &a)) }
        let first = laws.count
        switch station {
        case .xyz(let point):
            let weight = try remap(original.first.original.polynomials[3], offset: 0, into: p, field: field, &a)
            for axis in 0..<3 {
                let value = try field.importing(axis == 0 ? point.x : axis == 1 ? point.y : point.z, using: &a)
                let h = try remap(original.first.original.polynomials[axis], offset: 0, into: p, field: field, &a)
                laws.append(try p.subtracting(p.multiplying(p.constant(value, using: &a), weight, using: &a), h, using: &a))
            }
        case .curveParameter(_, let input):
            guard original.kind == .curveSurface else { throw ExactGeometricRelationFailure.invalidStation }
            let value = try field.importing(input, using: &a)
            try requireStation(value, axis: 0, in: original, field: field, &a)
            laws.append(try p.subtracting(p.variable(0, using: &a), p.constant(value, using: &a), using: &a))
        case .firstSurfaceUV(let uv), .secondSurfaceUV(let uv):
            let offset: Int
            if case .firstSurfaceUV = station {
                guard original.first.parameterCount == 2 else { throw ExactGeometricRelationFailure.invalidStation }
                offset = 0
            } else { offset = original.first.parameterCount }
            let u = try field.importing(uv.u, using: &a), v = try field.importing(uv.v, using: &a)
            try requireStation(u, axis: offset, in: original, field: field, &a)
            try requireStation(v, axis: offset + 1, in: original, field: field, &a)
            laws.append(try p.subtracting(p.variable(offset, using: &a), p.constant(u, using: &a), using: &a))
            laws.append(try p.subtracting(p.variable(offset + 1, using: &a), p.constant(v, using: &a), using: &a))
        }
        let source = try cells.bind(polynomials: laws, domains: original.predicate.source.domains, using: &a)
        let count = try ExactGeometryAccess.add(original.predicate.instructions.count, try ExactGeometryAccess.multiply(laws.count - first, 2))
        try ExactGeometryAccess.storage(count, ExactRealCellInstruction.self, &a)
        var instructions: [ExactRealCellInstruction] = []; instructions.reserveCapacity(count)
        for instruction in original.predicate.instructions { try a.consumeWork(1); instructions.append(instruction) }
        for index in first..<laws.count { instructions.append(.sign(polynomial: index, relation: .equal)); instructions.append(.and) }
        return (cells, try cells.predicate(instructions: instructions, for: source, using: &a))
    }

    func requireStation<A: ExactScalarAdmission & ~Copyable>(_ value: Field.Value, axis: Int,
        in original: ExactParametricRelationSource<Base>, field: Field, _ a: inout A) throws {
        let box = original.predicate.source.domains[axis]
        guard !box.isEmpty else { throw ExactGeometricRelationFailure.invalidStation }
        if case .finite(let lower) = box.lower {
            let order = try field.compare(value, field.importing(lower, using: &a), using: &a)
            guard order != .less, order != .equal || box.includesLower else { throw ExactGeometricRelationFailure.invalidStation }
        }
        if case .finite(let upper) = box.upper {
            let order = try field.compare(value, field.importing(upper, using: &a), using: &a)
            guard order != .greater, order != .equal || box.includesUpper else { throw ExactGeometricRelationFailure.invalidStation }
        }
    }

    public func contains<A: ExactScalarAdmission & ~Copyable>(_ point: borrowing ExactXYZ<Base>,
        in relation: borrowing ExactGeometricRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> Bool {
        do {
            let station = ExactGeometricStation.xyz(copy point)
            let (cells, predicate) = try stationPredicate(station, in: relation, &admission)
            let partition = try cells.decompose(predicate.source, limits: limits.cells, using: &admission)
            let selection = try cells.select(partition, matching: predicate, using: &admission)
            let result = !selection.cells.isEmpty
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }

    public func fiber<A: ExactScalarAdmission & ~Copyable>(at station: borrowing ExactGeometricStation<Base>,
        in relation: borrowing ExactGeometricRelation<Base>, limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricFiber<Base> {
        do {
            let (cells, predicate) = try stationPredicate(station, in: relation, &admission)
            let partition = try cells.decompose(predicate.source, limits: limits.cells, using: &admission)
            let selection = try cells.select(partition, matching: predicate, using: &admission)
            let incidence = try topology.incidence(of: selection, strategy: .automatic, limits: limits.topology, using: &admission)
            let components = try topology.components(of: incidence, limits: limits.topology, using: &admission)
            try ExactGeometryAccess.storage(1, ExactGeometricFiber<Base>.self, &admission)
            let result = ExactGeometricFiber(parent: copy relation, station: copy station, components: components)
            try admission.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
