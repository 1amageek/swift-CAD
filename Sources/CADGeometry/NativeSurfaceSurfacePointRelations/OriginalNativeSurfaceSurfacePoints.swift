import CADCore

/// Immutable complete original-source coverage and exact isolated tuple authority.
public final class OriginalNativeSurfaceSurfacePoints: Sendable {
    public let firstSurface: BSplineSurface3D
    public let secondSurface: BSplineSurface3D
    public let certificationTolerance: ModelingTolerance
    public var sourceChartCount: Int { coverage.sourceChartCount }
    public func sourceChart(at ordinal: Int) throws -> OriginalNativeSurfaceSurfaceChart { try coverage.sourceChart(at: ordinal) }
    public var nativeDomains: [OriginalRationalParameterDomain] { coverage.nativeDomains }
    public var requestedDomains: [OriginalRationalParameterDomain] { coverage.requestedDomains }
    public var effectiveDomains: [OriginalRationalParameterDomain]? { coverage.effectiveDomains }
    public var count: Int { cellIndices.count }
    package let coverage: NativeSurfaceSurfaceCoverage
    package let cellIndices: [Int]
    private let parameterIsolations: [OriginalSingularFieldValueIsolation]
    let parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]

    init(first: BSplineSurface3D, second: BSplineSurface3D,
        tolerance: ModelingTolerance, decomposition: OriginalRationalIntersectionDecomposition,
        cellIndices: [Int], parameterIsolations: [OriginalSingularFieldValueIsolation],
        parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]) {
        firstSurface = first; secondSurface = second; certificationTolerance = tolerance
        self.coverage = .single(decomposition); self.cellIndices = cellIndices
        self.parameterIsolations = parameterIsolations
        self.parameterLocalizations = parameterLocalizations
    }

    init(first: BSplineSurface3D, second: BSplineSurface3D,
        tolerance: ModelingTolerance, coverage: NativeSurfaceSurfaceCoverage,
        cellIndices: [Int], parameterIsolations: [OriginalSingularFieldValueIsolation],
        parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]) {
        firstSurface = first; secondSurface = second; certificationTolerance = tolerance
        self.coverage = coverage; self.cellIndices = cellIndices
        self.parameterIsolations = parameterIsolations; self.parameterLocalizations = parameterLocalizations
    }

    public func sourceChartIndex(for point: OriginalNativeSurfaceSurfacePoint) throws -> Int {
        guard owns(point) else { throw GeometryConversionError.invalidInput("Native chart access requires its owning point receipt.") }
        return coverage.chartIndex(cellIndex: cellIndices[point.ordinal])
    }

    public func point(at index: Int) throws -> OriginalNativeSurfaceSurfacePoint {
        guard cellIndices.indices.contains(index) else {
            throw GeometryConversionError.invalidInput("Native point index is outside its complete receipt.")
        }
        return .init(owner: self, ordinal: index)
    }

    public func owns(_ point: OriginalNativeSurfaceSurfacePoint) -> Bool {
        point.owner === self && cellIndices.indices.contains(point.ordinal)
    }

    package func parameterIsolation(at ordinal: Int, axis: Int) throws -> OriginalSingularFieldValueIsolation {
        guard cellIndices.indices.contains(ordinal), (0..<4).contains(axis),
            parameterIsolations.count == cellIndices.count * 4 else {
            throw GeometryConversionError.invalidInput("Native coordinate requires its retained localization receipt.")
        }
        return parameterIsolations[ordinal * 4 + axis]
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
        guard partition.cells.indices.contains(cellIndex), (0..<4).contains(axis) else {
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
        guard cellIndices.indices.contains(index), let partition = coverage.partition else {
            throw GeometryConversionError.invalidInput("Native point is not owned by this coverage receipt.")
        }
        return partition.cells[cellIndices[index]]
    }
}
