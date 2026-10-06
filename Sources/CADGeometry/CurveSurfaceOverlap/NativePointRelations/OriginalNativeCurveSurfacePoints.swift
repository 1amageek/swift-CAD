import CADCore

/// Immutable complete original-source coverage and exact isolated tuple authority.
public final class OriginalNativeCurveSurfacePoints: Sendable {
    public let curve: BSplineCurve3D
    public let surface: BSplineSurface3D
    public let certificationTolerance: ModelingTolerance
    public var nativeDomains: [OriginalRationalParameterDomain] { decomposition.nativeDomains }
    public var requestedDomains: [OriginalRationalParameterDomain] { decomposition.requestedDomains }
    public var effectiveDomains: [OriginalRationalParameterDomain]? { decomposition.effectiveDomains }
    public var count: Int { cellIndices.count }
    package let decomposition: OriginalRationalIntersectionDecomposition
    package let cellIndices: [Int]
    private let parameterIsolations: [OriginalSingularFieldValueIsolation]
    let parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]

    init(curve: BSplineCurve3D, surface: BSplineSurface3D,
        tolerance: ModelingTolerance, decomposition: OriginalRationalIntersectionDecomposition,
        cellIndices: [Int], parameterIsolations: [OriginalSingularFieldValueIsolation],
        parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]) {
        self.curve = curve; self.surface = surface; certificationTolerance = tolerance
        self.decomposition = decomposition; self.cellIndices = cellIndices
        self.parameterIsolations = parameterIsolations
        self.parameterLocalizations = parameterLocalizations
    }

    public func point(at index: Int) throws -> OriginalNativeCurveSurfacePoint {
        guard cellIndices.indices.contains(index) else {
            throw GeometryConversionError.invalidInput("Native point index is outside its complete receipt.")
        }
        return .init(owner: self, ordinal: index)
    }

    public func owns(_ point: OriginalNativeCurveSurfacePoint) -> Bool {
        point.owner === self && cellIndices.indices.contains(point.ordinal)
    }

    package func parameterIsolation(at ordinal: Int, axis: Int) throws -> OriginalSingularFieldValueIsolation {
        guard cellIndices.indices.contains(ordinal), (0..<3).contains(axis),
            parameterIsolations.count == cellIndices.count * 3 else {
            throw GeometryConversionError.invalidInput("Native coordinate requires its retained localization receipt.")
        }
        return parameterIsolations[ordinal * 3 + axis]
    }

    package static func sectionBounds(partition: OriginalRationalIntersectionCells, cellIndex: Int, axis: Int)
        throws -> (lower: ExactRationalCoefficient, upper: ExactRationalCoefficient) {
        let index = try sectionCellIndex(partition: partition, cellIndex: cellIndex, axis: axis)
        let cell = partition.cells[index], stack = partition.stacks[cell.stackIndex]
        guard case .section(let rootOrdinal) = cell.kind, stack.roots.indices.contains(rootOrdinal) else {
            throw rationalAlgebraFailure("A zero-dimensional native tuple lost its original section root.")
        }
        let bounds = stack.roots[rootOrdinal].isolation
        return (bounds.lower, bounds.upper)
    }

    static func sectionCellIndex(partition: OriginalRationalIntersectionCells, cellIndex: Int, axis: Int) throws -> Int {
        guard partition.cells.indices.contains(cellIndex), (0..<3).contains(axis) else {
            throw GeometryConversionError.invalidInput("Native coordinate seed requires its owning original section.")
        }
        var index = cellIndex
        while true {
            let cell = partition.cells[index], stack = partition.stacks[cell.stackIndex]
            if stack.axis == axis {
                guard case .section(let rootOrdinal) = cell.kind, stack.roots.indices.contains(rootOrdinal) else {
                    throw rationalAlgebraFailure("A zero-dimensional native tuple lost its original section root.")
                }
                return index
            }
            guard stack.axis > axis, let parent = stack.parentCell else {
                throw rationalAlgebraFailure("Native coordinate seed lost its complete parent stack.")
            }
            index = parent
        }
    }

    package func cell(at index: Int) throws -> OriginalRationalIntersectionCells.Cell {
        guard cellIndices.indices.contains(index), case .parameterCells(let strata, _, _) = decomposition.coverage else {
            throw GeometryConversionError.invalidInput("Native point is not owned by this coverage receipt.")
        }
        return strata.partition.cells[cellIndices[index]]
    }
}
