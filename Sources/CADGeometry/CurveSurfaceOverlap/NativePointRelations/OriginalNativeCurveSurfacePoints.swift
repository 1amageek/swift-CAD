import CADCore

/// Immutable original-source coverage and exact isolated-component tuple authority.
public final class OriginalNativeCurveSurfacePoints: Sendable {
    public let curve: BSplineCurve3D
    public let surface: BSplineSurface3D
    public let certificationTolerance: ModelingTolerance
    public let nativeDomains: [OriginalRationalParameterDomain]
    public let requestedDomains: [OriginalRationalParameterDomain]
    public let effectiveDomains: [OriginalRationalParameterDomain]?
    public var count: Int { pointCells.count }
    /// Every closed original span product, including complete exclusion proofs.
    public var coverageChartCount: Int { charts.count }
    package let charts: [NativeCurveSurfacePointChart]
    package let composedPartition: OriginalRationalIntersectionCells?
    package let pointCells: [NativeCurveSurfacePointCell]
    private let parameterIsolations: [OriginalSingularFieldValueIsolation]
    let parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]

    init(curve: BSplineCurve3D, surface: BSplineSurface3D,
        tolerance: ModelingTolerance, nativeDomains: [OriginalRationalParameterDomain],
        requestedDomains: [OriginalRationalParameterDomain], effectiveDomains: [OriginalRationalParameterDomain]?,
        charts: [NativeCurveSurfacePointChart], composedPartition: OriginalRationalIntersectionCells? = nil, pointCells: [NativeCurveSurfacePointCell],
        parameterIsolations: [OriginalSingularFieldValueIsolation],
        parameterLocalizations: [NativeCurveSurfaceScalarLocalization?]) {
        self.curve = curve; self.surface = surface; certificationTolerance = tolerance
        self.nativeDomains = nativeDomains; self.requestedDomains = requestedDomains
        self.effectiveDomains = effectiveDomains; self.charts = charts; self.composedPartition = composedPartition; self.pointCells = pointCells
        self.parameterIsolations = parameterIsolations
        self.parameterLocalizations = parameterLocalizations
    }

    public func point(at index: Int) throws -> OriginalNativeCurveSurfacePoint {
        guard pointCells.indices.contains(index) else {
            throw GeometryConversionError.invalidInput("Native point index is outside its complete receipt.")
        }
        return .init(owner: self, ordinal: index)
    }

    public func owns(_ point: OriginalNativeCurveSurfacePoint) -> Bool {
        point.owner === self && pointCells.indices.contains(point.ordinal)
    }

    package func parameterIsolation(at ordinal: Int, axis: Int) throws -> OriginalSingularFieldValueIsolation {
        guard pointCells.indices.contains(ordinal), (0..<3).contains(axis),
            parameterIsolations.count == pointCells.count * 3 else {
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
        guard pointCells.indices.contains(index) else {
            throw GeometryConversionError.invalidInput("Native point is not owned by this coverage receipt.")
        }
        let reference = pointCells[index]
        if let composedPartition {
            guard charts.indices.contains(reference.chartIndex), composedPartition.solutionCells.contains(reference.cellIndex) else {
                throw GeometryConversionError.invalidInput("Native point lost its owning common-refinement cell.")
            }
            return composedPartition.cells[reference.cellIndex]
        }
        guard charts.indices.contains(reference.chartIndex),
            case .parameterCells(let strata, _, _) = charts[reference.chartIndex].decomposition.coverage,
            strata.partition.cells.indices.contains(reference.cellIndex) else {
            throw GeometryConversionError.invalidInput("Native point lost its owning original chart cell.")
        }
        return strata.partition.cells[reference.cellIndex]
    }
}
