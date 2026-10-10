#if L6_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
#endif

extension DefaultExactGeometricGraphRelationResolver {
    public func point<A: ExactScalarAdmission & ~Copyable>(atParameterOrdinal ordinal: Int,
        in relation: borrowing ExactGeometricGraphRelation<Base>, using a: inout A
    ) throws(ExactGeometricRelationFailure) -> ExactGeometricGraphPoint<Base> {
        do {
            try a.checkpoint(); try a.admitDepth(value: relation.depth.value, coefficient: relation.depth.coefficient)
            let projection = relation.original.projection
            guard ordinal >= 0, ordinal < projection.selection.cells.count,
                projection.selection.cells[ordinal].dimension == 0,
                let lifts = projection.liftedCells(forProjectedOrdinal: ordinal), let cell = lifts.first else {
                throw ExactGeometricRelationFailure.invalidStation
            }
            var componentFound = false
            for members in relation.original.components.memberRanges {
                var contains = false
                for index in members { try a.consumeWork(1); if relation.original.components.members[index] == projection.selection.cells[ordinal] { contains = true } }
                if contains {
                    componentFound = true
                    for index in members { try a.consumeWork(1); guard relation.original.components.members[index].dimension == 0 else { throw ExactGeometricRelationFailure.invalidStation } }
                }
            }
            guard componentFound else { throw ExactGeometricRelationFailure.invalidCoverage }
            let cells = try Cells(retaining: projection.original.partition.source, using: &a)
            let sample = try cells.sample(of: cell, in: projection.original.partition, using: &a)
            let original = relation.original.original, position = original.first.predicate.source.polynomials
            let ring = try ExactPolynomialDomain(field: sample.field, variableCount: original.first.variableCount, using: &a)
            try ExactGeometryAccess.storage(original.first.variableCount, Field.Value.self, &a)
            var coordinates: [Field.Value] = []; coordinates.reserveCapacity(original.first.variableCount)
            for index in original.firstCoordinates { try a.consumeWork(1); coordinates.append(sample.coordinates[index]) }
            let weight = try ring.evaluated(ring.importing(position[3], using: &a), at: coordinates, using: &a).value
            try ExactGeometryAccess.storage(3, Field.Value.self, &a)
            var xyz: [Field.Value] = []; xyz.reserveCapacity(3)
            for axis in 0..<3 {
                let numerator = try ring.evaluated(ring.importing(position[axis], using: &a), at: coordinates, using: &a).value
                xyz.append(try sample.field.dividing(numerator, weight, using: &a))
            }
            try ExactGeometryAccess.storage(original.parameterCount, Field.Value.self, &a)
            var parameters: [Field.Value] = []; parameters.reserveCapacity(original.parameterCount)
            for i in 0..<original.parameterCount { try a.consumeWork(1); parameters.append(sample.coordinates[i]) }
            let point = ExactXYZ(field: sample.field, x: xyz[0], y: xyz[1], z: xyz[2])
            try ExactGeometryAccess.storage(1, ExactGeometricGraphPoint<Base>.self, &a)
            let result = ExactGeometricGraphPoint(parent: copy relation, parameterOrdinal: ordinal, witness: sample, parameters: parameters, position: point)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
