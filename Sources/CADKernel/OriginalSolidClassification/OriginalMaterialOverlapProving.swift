import CADCore
import CADGeometry
import CADTopology

/// Positive material proof from the same source-bound producer graph; false is inconclusive.
package protocol OriginalMaterialOverlapProving: Sendable {
    func interiorWitness(in classifications: PreparedSolidClassificationPair,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> Point3D?
    func interiorWitness(in prepared: PreparedBooleanIntersectionGraph,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws -> Point3D?
    func provesOverlap(in prepared: PreparedBooleanIntersectionGraph,
        firstBodyID: BodyID, secondBodyID: BodyID,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws -> Bool
    func provesOverlap(inAdmitted graph: BooleanIntersectionGraph,
        firstBodyID: BodyID, secondBodyID: BodyID, validatedModel: ValidatedBRepModel,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws -> Bool
}
