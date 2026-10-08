import CADCore

/// Source adapter only; all solving and topology remain in the exact layers.
public struct DefaultNativeExactRelationResolver:
    NativeExactCurveSurfaceResolving, NativeExactSurfaceSurfaceResolving {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Cells = ExactRealCellDomain<ExactRationalScalarDomain>
    typealias Domain = ExactParametricRelationDomain<ExactRationalScalarDomain,
        Cells, ExactRealTopology<ExactRationalScalarDomain>>

    public init() {}

    public func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D, surface: BSplineSurface3D,
        curveRange: ScalarInterval? = nil, surfaceDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: 0, coefficient: 0)
            let field = try Field.base(field: .init(), maximumExtensionLevel: maximumExtensionLevel, using: &admission)
            let first = try curveMap(curve, selected: curveRange, field: field,
                tolerance: tolerance, degree: maximumPolynomialDegree, using: &admission)
            let second = try surfaceMap(surface, selected: surfaceDomain, field: field,
                tolerance: tolerance, degree: maximumPolynomialDegree, using: &admission)
            return try publish(first: first, second: second, field: field,
                source: .curveSurface(curve: curve, surface: surface,
                    curveRange: curveRange, surfaceDomain: surfaceDomain),
                kind: .curveSurface, tolerance: tolerance,
                cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
        } catch { throw .preserving(error) }
    }

    public func exactParameterRelation<A: ExactScalarAdmission & ~Copyable>(
        first: BSplineSurface3D, second: BSplineSurface3D,
        firstDomain: SurfaceParameterBox? = nil, secondDomain: SurfaceParameterBox? = nil,
        tolerance: ModelingTolerance, maximumPolynomialDegree: Int,
        maximumExtensionLevel: Int, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactParametricRelation {
        do {
            try admission.checkpoint()
            try admission.admitDepth(value: 0, coefficient: 0)
            let field = try Field.base(field: .init(), maximumExtensionLevel: maximumExtensionLevel, using: &admission)
            let a = try surfaceMap(first, selected: firstDomain, field: field,
                tolerance: tolerance, degree: maximumPolynomialDegree, using: &admission)
            let b = try surfaceMap(second, selected: secondDomain, field: field,
                tolerance: tolerance, degree: maximumPolynomialDegree, using: &admission)
            return try publish(first: a, second: b, field: field,
                source: .surfaceSurface(first: first, second: second,
                    firstDomain: firstDomain, secondDomain: secondDomain),
                kind: .surfaceSurface, tolerance: tolerance,
                cellLimits: cellLimits, topologyLimits: topologyLimits, using: &admission)
        } catch { throw .preserving(error) }
    }

    private func publish<A: ExactScalarAdmission & ~Copyable>(
        first: NativeExactPreparedMap,
        second: NativeExactPreparedMap, field: Field,
        source: NativeExactRelationSource, kind: ExactParametricRelationKind,
        tolerance: ModelingTolerance, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using admission: inout A
    ) throws -> NativeExactParametricRelation {
        let d = Domain(cells: Cells.self, topology: .init(cells: Cells.self))
        let compiled = try d.compile(kind: kind, first: first.map, second: second.map, using: &admission)
        let relation = try d.resolve(compiled, cellLimits: cellLimits,
            topologyLimits: topologyLimits, using: &admission)
        try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: NativeExactParametricRelation.self))
        let result = NativeExactParametricRelation(source: source, tolerance: tolerance,
            coefficientField: field, relation: relation)
        try admission.checkpoint()
        withExtendedLifetime(first.sourceLaw) {}
        withExtendedLifetime(second.sourceLaw) {}
        return result
    }
}
