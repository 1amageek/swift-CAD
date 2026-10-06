import CADCore
import CADIR
import CADTopology

/// Resolves dimensional admission through a protocol requirement on every target.
public protocol BooleanDimensionResolving: Sendable {
    func resolve(feature: BooleanFeature, targets: [any ShapeRepresenting],
                 tools: [any ShapeRepresenting], tolerance: ModelingTolerance) throws -> BooleanDimensionContract
}
