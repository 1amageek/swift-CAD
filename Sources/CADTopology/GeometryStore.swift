import HashTreeCollections
import CADCore
import CADGeometry

public struct GeometryStore: Equatable, Sendable {
    public var curves: PersistentMap<CurveID, Curve3D>
    public var surfaces: PersistentMap<SurfaceID, Surface3D>

    public init(curves: [CurveID: Curve3D] = [:], surfaces: [SurfaceID: Surface3D] = [:]) {
        self.curves = PersistentMap(curves)
        self.surfaces = PersistentMap(surfaces)
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case curves
        case surfaces
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.curves, .surfaces], in: decoder)
        curves = try container.decode(
            PersistentMap<CurveID, Curve3D>.self,
            forKey: .curves
        )
        surfaces = try container.decode(
            PersistentMap<SurfaceID, Surface3D>.self,
            forKey: .surfaces
        )
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(curves, forKey: .curves)
        try container.encode(surfaces, forKey: .surfaces)
    }
    #endif

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
        try validate(tolerance: tolerance, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 32, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        for curve in curves.values {
            try execution.consumeWork(1)
            try curve.validate(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        for surface in surfaces.values {
            try execution.consumeWork(1)
            try surface.validate(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
    }

}

#if !hasFeature(Embedded)
extension GeometryStore: Codable {}
#endif
