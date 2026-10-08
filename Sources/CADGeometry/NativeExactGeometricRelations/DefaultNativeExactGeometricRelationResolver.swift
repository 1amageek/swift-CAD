/// Interprets one retained original parameter relation without resolving it again.
public struct DefaultNativeExactGeometricRelationResolver: Sendable {
    public init() {}

    public func resolve<A: ExactScalarAdmission & ~Copyable>(
        _ source: borrowing NativeExactParametricRelation,
        limits: ExactGeometricRelationLimits, using admission: inout A
    ) throws(NativeExactGeometricRelationFailure) -> NativeExactGeometricRelation {
        do {
            typealias Base = ExactRationalScalarDomain
            typealias Cells = ExactRealCellDomain<Base>
            let resolver = DefaultExactGeometricRelationResolver(
                cells: Cells.self, topology: ExactRealTopology<Base>(cells: Cells.self))
            let geometry = try resolver.resolve(source.relation, limits: limits, using: &admission)
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1,
                of: NativeExactGeometricRelation.self))
            var positiveParameters = false, positiveImage = false
            for record in geometry.strata {
                try admission.consumeWork(1)
                positiveParameters = positiveParameters || record.parameterDimension > 0
                positiveImage = positiveImage || record.imageDimension > 0
            }
            let result = NativeExactGeometricRelation(parameterRelation: copy source, geometry: geometry,
                hasPositiveDimensionalSolutions: positiveParameters, hasPositiveDimensionalImage: positiveImage)
            try admission.checkpoint()
            return result
        } catch { throw .preserving(error) }
    }
}
