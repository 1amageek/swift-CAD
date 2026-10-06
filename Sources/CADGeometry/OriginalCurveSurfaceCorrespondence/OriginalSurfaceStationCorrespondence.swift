import CADCore
import Foundation

/// Reuses original closed native jets for physical edge-to-pcurve station transfer.
package struct OriginalSurfaceStationCorrespondence: OriginalSurfaceStationCorrespondenceResolving {
    private let curve: Curve3D
    private let startParameter: Double
    private let endParameter: Double
    private let surface: Surface3D
    private let parameterCurve: SurfaceParameterCurve
    private let tolerance: ModelingTolerance
    private let spatial: PreparedCurveDifferentialEncloser
    private let lifted: PreparedCurveDifferentialEncloser
    private let maximumSpanCount: Int
    private let preparationDepth: Int
    private let remainingSourceDepth: Int

    package init(curve: Curve3D, from startParameter: Double, to endParameter: Double,
        surface: Surface3D, parameterCurve: SurfaceParameterCurve,
        tolerance: ModelingTolerance, maximumSpanCount: Int = Int.max,
        maximumSubdivisionDepth: Int = 32, remainingSourceDepth: Int = Int.max,
        consumeWork: () throws -> Void) throws {
        try consumeWork()
        try tolerance.validate()
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 32, remainingSourceDepth >= 0 else {
            throw Self.failure(.invalidInput, tolerance, "Station preparation requires the composing original ceilings.")
        }
        self.maximumSpanCount = maximumSpanCount
        preparationDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        guard startParameter.isFinite, endParameter.isFinite, startParameter != endParameter,
              try curve.parameterDomain.containsSpan(from: startParameter, to: endParameter,
                tolerance: tolerance) else {
            throw Self.failure(.invalidInput, tolerance, "Station correspondence requires an original finite directed edge trim.")
        }
        self.curve = curve
        self.startParameter = startParameter
        self.endParameter = endParameter
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.tolerance = tolerance
        spatial = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork)
        lifted = try PreparedCurveDifferentialEncloser(curve: .surfaceLift(.init(
            surface: surface, parameterCurve: parameterCurve)), tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This original station producer closes
    // transverse local coordinate branches consumed by mesh station transfer.
    // Global stationary/critical branch atlases and missing-pcurve reconstruction
    // remain required before this port represents every mandatory correspondence.
    package func resolve(stationParameter: Double, maximumDeviation: Double,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws
        -> OriginalSurfaceStationCorrespondenceReceipt {
        try Task.checkCancellation()
        guard stationParameter.isFinite,
              stationParameter >= min(startParameter, endParameter),
              stationParameter <= max(startParameter, endParameter),
              maximumDeviation.isFinite, maximumDeviation > 0,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32 else {
            throw Self.failure(.invalidInput, tolerance, "Original station inverse inputs are outside their retained directed use.")
        }
        let station = try jet(spatial, over: ScalarInterval(lower: stationParameter,
            upper: stationParameter), consumeWork: consumeWork)
        func receipt(_ fractions: ScalarInterval, _ bound: Double, _ orientation: Int)
            -> OriginalSurfaceStationCorrespondenceReceipt {
            .init(curve: curve, startParameter: startParameter, endParameter: endParameter,
                surface: surface, parameterCurve: parameterCurve,
                stationParameter: stationParameter, fractions: fractions,
                maximumDeviation: bound, orientation: orientation, tolerance: tolerance)
        }
        if stationParameter == startParameter || stationParameter == endParameter {
            let fraction = stationParameter == startParameter ? 0.0 : 1.0
            let range = try ScalarInterval(lower: fraction, upper: fraction)
            let bound = upperDistance(try jet(lifted, over: range,
                consumeWork: consumeWork), station)
            guard bound <= maximumDeviation else {
                throw Self.failure(.topologyFailure, tolerance, "Authored original use endpoint does not match the spatial edge endpoint.")
            }
            return receipt(range, bound, 1)
        }
        let coordinates = [station.x, station.y, station.z]
        let axes = coordinates.indices.filter { coordinates[$0].derivativeU.lower > 0
            || coordinates[$0].derivativeU.upper < 0 }
        guard let axis = axes.max(by: { strength(coordinates[$0].derivativeU)
            < strength(coordinates[$1].derivativeU) }) else {
            throw Self.failure(.singularGeometry, tolerance, "Original spatial station has no certified transverse coordinate.")
        }
        let target = coordinates[axis].value
        struct Cell { let range: ScalarInterval; let depth: Int }
        var pending = [Cell(range: try ScalarInterval(lower: 0, upper: 1), depth: 0)]
        var candidates: [ScalarInterval] = []
        var achieved = 0.0
        while let cell = pending.popLast() {
            try Task.checkCancellation(); try consumeWork()
            let image = try jet(lifted, over: cell.range, consumeWork: consumeWork)
            let residual = component(image, axis).value - target
            if residual.lower > 0 || residual.upper < 0
                || lowerDistance(image, station) > maximumDeviation { continue }
            let bound = upperDistance(image, station)
            if bound <= maximumDeviation {
                try consumeWork()
                candidates.append(cell.range)
                achieved = max(achieved, bound)
                continue
            }
            let middle = cell.range.midpoint
            guard cell.depth < maximumSubdivisionDepth,
                  middle > cell.range.lower, middle < cell.range.upper else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Original station inverse did not close its physical interval bound.")
            }
            pending.append(.init(range: try ScalarInterval(lower: middle,
                upper: cell.range.upper), depth: cell.depth + 1))
            pending.append(.init(range: try ScalarInterval(lower: cell.range.lower,
                upper: middle), depth: cell.depth + 1))
        }
        guard let first = candidates.first else {
            throw Self.failure(.topologyFailure, tolerance, "Original surface use has no physical match for the spatial station.")
        }
        // DFS visits fractions in increasing order; no unpaid sorting or seed selection.
        var lower = first.lower, upper = first.upper
        for range in candidates.dropFirst() {
            try consumeWork()
            guard range.lower <= upper else {
                throw Self.failure(.ambiguousSelection, tolerance, "Original station has multiple separated pcurve branches.")
            }
            lower = min(lower, range.lower); upper = max(upper, range.upper)
        }
        let range = try ScalarInterval(lower: lower, upper: upper)
        let derivative = component(try jet(lifted, over: range,
            consumeWork: consumeWork), axis).derivativeU
        let low = component(try jet(lifted, over: ScalarInterval(lower: lower,
            upper: lower), consumeWork: consumeWork), axis).value - target
        let high = component(try jet(lifted, over: ScalarInterval(lower: upper,
            upper: upper), consumeWork: consumeWork), axis).value - target
        let sign: Int
        if derivative.lower > 0, low.upper < 0, high.lower > 0 { sign = 1 }
        else if derivative.upper < 0, low.lower > 0, high.upper < 0 { sign = -1 }
        else {
            throw Self.failure(.classificationFailure, tolerance, "Original station root lacks strict bracket and one-sided monotone derivative authority.")
        }
        let spatialSign = coordinates[axis].derivativeU.lower > 0 ? 1 : -1
        let directedSign = endParameter > startParameter ? 1 : -1
        return receipt(range, achieved, sign * spatialSign * directedSign)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This reverse producer certifies
    // transverse original branches for mesh station propagation. General
    // stationary/critical correspondence still needs a complete retained atlas.
    package func resolve(liftFraction: Double, maximumDeviation: Double,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws
        -> OriginalSurfaceStationInverseReceipt {
        try Task.checkCancellation()
        guard liftFraction.isFinite, liftFraction >= 0, liftFraction <= 1,
              maximumDeviation.isFinite, maximumDeviation > 0,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32 else {
            throw Self.failure(.invalidInput, tolerance, "Original reverse station inputs lie outside their retained use.")
        }
        let station = try jet(lifted, over: .init(lower: liftFraction, upper: liftFraction),
            consumeWork: consumeWork)
        func receipt(_ native: ScalarInterval, _ bound: Double, _ orientation: Int)
            -> OriginalSurfaceStationInverseReceipt {
            .init(curve: curve, startParameter: startParameter, endParameter: endParameter,
                surface: surface, parameterCurve: parameterCurve, liftFraction: liftFraction,
                nativeParameters: native, maximumDeviation: bound, orientation: orientation,
                tolerance: tolerance)
        }
        if liftFraction == 0 || liftFraction == 1 {
            let parameter = liftFraction == 0 ? startParameter : endParameter
            let range = try ScalarInterval(lower: parameter, upper: parameter)
            let bound = upperDistance(try jet(spatial, over: range, consumeWork: consumeWork), station)
            guard bound <= maximumDeviation else {
                throw Self.failure(.topologyFailure, tolerance, "Original lifted endpoint differs from its directed spatial endpoint.")
            }
            return receipt(range, bound, 1)
        }
        let coordinates = [station.x, station.y, station.z]
        var selected: Int?
        for axis in coordinates.indices {
            try consumeWork()
            let derivative = coordinates[axis].derivativeU
            if derivative.lower > 0 || derivative.upper < 0 {
                if let previous = selected {
                    if strength(derivative) > strength(coordinates[previous].derivativeU) { selected = axis }
                } else { selected = axis }
            }
        }
        guard let axis = selected else {
            throw Self.failure(.singularGeometry, tolerance, "Original lifted station has no proved transverse coordinate.")
        }
        let target = coordinates[axis].value
        struct Cell { let range: ScalarInterval; let depth: Int }
        try consumeWork()
        var pending = [Cell(range: try .init(lower: min(startParameter, endParameter),
            upper: max(startParameter, endParameter)), depth: 0)]
        var candidates: [ScalarInterval] = []
        var achieved = 0.0
        while let cell = pending.popLast() {
            try Task.checkCancellation(); try consumeWork()
            let image = try jet(spatial, over: cell.range, consumeWork: consumeWork)
            let residual = component(image, axis).value - target
            if residual.lower > 0 || residual.upper < 0 || lowerDistance(image, station) > maximumDeviation { continue }
            let bound = upperDistance(image, station)
            if bound <= maximumDeviation {
                try consumeWork()
                candidates.append(cell.range)
                achieved = max(achieved, bound)
                continue
            }
            let middle = cell.range.midpoint
            guard cell.depth < maximumSubdivisionDepth,
                  middle > cell.range.lower, middle < cell.range.upper else {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Reverse original station did not close its whole physical bound.")
            }
            try consumeWork()
            pending.append(.init(range: try .init(lower: middle, upper: cell.range.upper), depth: cell.depth + 1))
            try consumeWork()
            pending.append(.init(range: try .init(lower: cell.range.lower, upper: middle), depth: cell.depth + 1))
        }
        guard let first = candidates.first else {
            throw Self.failure(.topologyFailure, tolerance, "Directed original spatial edge has no match for the lifted station.")
        }
        var lower = first.lower, upper = first.upper
        for range in candidates.dropFirst() {
            try consumeWork()
            guard range.lower <= upper else {
                throw Self.failure(.ambiguousSelection, tolerance, "Original lifted station has separated spatial native branches.")
            }
            lower = min(lower, range.lower); upper = max(upper, range.upper)
        }
        let range = try ScalarInterval(lower: lower, upper: upper)
        let derivative = component(try jet(spatial, over: range, consumeWork: consumeWork), axis).derivativeU
        let low = component(try jet(spatial, over: .init(lower: lower, upper: lower), consumeWork: consumeWork), axis).value - target
        let high = component(try jet(spatial, over: .init(lower: upper, upper: upper), consumeWork: consumeWork), axis).value - target
        let spatialSign: Int
        if derivative.lower > 0, low.upper < 0, high.lower > 0 { spatialSign = 1 }
        else if derivative.upper < 0, low.lower > 0, high.upper < 0 { spatialSign = -1 }
        else {
            throw Self.failure(.classificationFailure, tolerance, "Reverse original station lacks strict bracket and whole monotonicity.")
        }
        let liftedSign = coordinates[axis].derivativeU.lower > 0 ? 1 : -1
        let directedSign = endParameter > startParameter ? 1 : -1
        return receipt(range, achieved, spatialSign * liftedSign * directedSign)
    }

    private func jet(_ owner: PreparedCurveDifferentialEncloser, over range: ScalarInterval,
        consumeWork: () throws -> Void) throws -> SurfaceIntervalVectorJet {
        let receipt = try owner.closedNativeJets(over: range, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: preparationDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork)
        guard let first = receipt.spans.first else {
            throw Self.failure(.classificationFailure, tolerance, "Original station source has no owning closed span.")
        }
        var result = first.jet
        for span in receipt.spans.dropFirst() {
            try consumeWork()
            result = result.union(span.jet)
        }
        return result
    }

    private func component(_ jet: SurfaceIntervalVectorJet, _ axis: Int) -> SurfaceIntervalJet {
        axis == 0 ? jet.x : axis == 1 ? jet.y : jet.z
    }

    private func strength(_ interval: OutwardScalarInterval) -> Double {
        interval.lower > 0 ? interval.lower : -interval.upper
    }

    private func upperDistance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet) -> Double {
        let differences = [a.x.value - b.x.value, a.y.value - b.y.value, a.z.value - b.z.value]
        var squared = OutwardScalarInterval.exact(0)
        for difference in differences {
            let magnitude = max(abs(difference.lower), abs(difference.upper))
            squared = squared + .exact(magnitude) * .exact(magnitude)
        }
        return sqrt(max(0, squared.upper)).nextUp
    }

    private func lowerDistance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet) -> Double {
        let differences = [a.x.value - b.x.value, a.y.value - b.y.value, a.z.value - b.z.value]
        var squared = OutwardScalarInterval.exact(0)
        for difference in differences {
            let magnitude = difference.lower > 0 ? difference.lower
                : difference.upper < 0 ? -difference.upper : 0
            squared = squared + .exact(magnitude) * .exact(magnitude)
        }
        return max(0, sqrt(max(0, squared.lower)).nextDown)
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
        _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
