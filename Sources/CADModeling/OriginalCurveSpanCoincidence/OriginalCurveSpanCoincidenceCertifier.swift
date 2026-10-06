import CADCore
import CADGeometry
import CADTopology
import Foundation

/// Proves correspondence on both complete original spans using outward native jets.
package struct OriginalCurveSpanCoincidenceCertifier {
    private struct Cell {
        let firstStart: Double
        let firstEnd: Double
        let secondStart: Double
        let secondEnd: Double
        let depth: Int
    }

    private struct ContinuityUsage: RationalAlgebraAdmitting {
        let admission: GeometryConversionAdmission?
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation()
            if let admission {
                guard depth >= 0, admission.maximumAlgebraicDepth.map({ depth <= $0 }) ?? true else {
                    throw GeometryConversionError.resourceLimitExceeded("Original coincidence exhausted exact algebra depth.")
                }
                try admission.chargeWork()
            }
        }
        mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0 else { throw GeometryConversionError.invalidInput("Coincidence work must be nonnegative.") }
            try Task.checkCancellation()
            try admission?.chargeWork(count)
        }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original coincidence storage overflows.")
            }
            try Task.checkCancellation()
            try admission?.chargeStorage(bytes: bytes.partialValue)
        }
    }

    private struct Source {
        let prepared: PreparedCurveDifferentialEncloser
        let continuous: Bool
        let admission: GeometryConversionAdmission?

        init(curve: Curve3D, parameters: ScalarInterval, tolerance: ModelingTolerance,
            admission: GeometryConversionAdmission?) throws {
            self.admission = admission
            if let admission {
                prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) },
                    maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
            } else {
                prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance)
            }
            var usage = ContinuityUsage(admission: admission)
            continuous = try prepared.admittingContinuousFirstOrder(over: parameters,
                tolerance: tolerance,
                maximumSubdivisionDepth: min(24, admission?.maximumSubdivisionDepth ?? 24),
                remainingSourceDepth: admission?.remainingSourceDepth ?? Int.max,
                usage: &usage) != nil
        }

        func jet(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
            let cover: PreparedCurveDifferentialEncloser.ClosedNativeJet
            if let admission {
                cover = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
                    maximumSpanCount: admission.maximumSpanCount,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                    remainingSourceDepth: admission.remainingSourceDepth,
                    consumeWork: { try admission.chargeWork() },
                    consumeStorage: { try admission.chargeStorage(bytes: $0) })
            } else {
                cover = try prepared.closedNativeJets(over: parameters, tolerance: tolerance,
                    consumeWork: { try Task.checkCancellation() })
            }
            guard let first = cover.spans.first else {
                throw GeometryConversionError.invalidInput("Original coincidence has no closed owning cover.")
            }
            var result = first.jet
            for span in cover.spans.dropFirst() {
                try Task.checkCancellation()
                try admission?.chargeWork()
                result = result.union(span.jet)
            }
            return result
        }
    }

    package init() {}

    package func matches(_ first: CurveSpanDefinition, _ second: CurveSpanDefinition,
        orientation: Orientation, tolerance: ModelingTolerance) throws -> Bool {
        try matches(first, second, orientation: orientation, tolerance: tolerance, admission: nil)
    }

    package func matches(_ first: CurveSpanDefinition, _ second: CurveSpanDefinition,
        orientation: Orientation, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> Bool {
        try matches(first, second, orientation: orientation, tolerance: tolerance,
            admission: Optional(admission))
    }

    private func matches(_ first: CurveSpanDefinition, _ second: CurveSpanDefinition,
        orientation: Orientation, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission?) throws -> Bool {
        let firstRange = try ScalarInterval(lower: min(first.startParameter, first.endParameter),
            upper: max(first.startParameter, first.endParameter))
        let secondRange = try ScalarInterval(lower: min(second.startParameter, second.endParameter),
            upper: max(second.startParameter, second.endParameter))
        guard firstRange.lower < firstRange.upper, secondRange.lower < secondRange.upper else {
            throw GeometryConversionError.invalidInput("Original coincidence needs two finite positive native spans.")
        }
        let firstSource = try Source(curve: first.curve, parameters: firstRange,
            tolerance: tolerance, admission: admission)
        let secondSource = try Source(curve: second.curve, parameters: secondRange,
            tolerance: tolerance, admission: admission)
        let secondStart = orientation == .forward ? second.startParameter : second.endParameter
        let secondEnd = orientation == .forward ? second.endParameter : second.startParameter
        if let admission {
            try GeometryStructuralComparisonWork.charge(curve: first.curve, using: admission.chargeWork)
            try GeometryStructuralComparisonWork.charge(curve: second.curve, using: admission.chargeWork)
        }
        if first.startParameter == secondStart, first.endParameter == secondEnd, first.curve == second.curve {
            return true
        }
        let maximumDepth = min(24, admission?.maximumSubdivisionDepth ?? 24)
        if let admission {
            let count = maximumDepth.addingReportingOverflow(1)
            let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<Cell>.stride)
            guard !count.overflow, !bytes.overflow else { throw failure("Original coincidence capacity overflows.", tolerance) }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        var cells: [Cell] = []
        cells.reserveCapacity(maximumDepth + 1)
        cells.append(Cell(firstStart: first.startParameter, firstEnd: first.endParameter,
            secondStart: secondStart, secondEnd: secondEnd, depth: 0))
        var remainingCells = 131_072
        while let cell = cells.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try admission?.visit(depth: cell.depth)
            guard remainingCells > 0 else { throw failure("Original curve coincidence exhausted its cell budget.", tolerance) }
            remainingCells -= 1
            if try certifies(cell, first: firstSource, second: secondSource, tolerance: tolerance) { continue }
            guard cell.depth < maximumDepth else { throw failure("Original curve coincidence exhausted its subdivision depth.", tolerance) }
            let firstMiddle = cell.firstStart * 0.5 + cell.firstEnd * 0.5
            let secondMiddle: Double
            if admission != nil {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Fillet and finite-contact
                // bounded callers use original paired affine cells here. Complete
                // nonlinear projection/correspondence needs its same-caller issuer;
                // legacy projection with reset counters cannot authorize this path.
                secondMiddle = cell.secondStart * 0.5 + cell.secondEnd * 0.5
            } else {
                let point = try first.curve.point(at: firstMiddle, tolerance: tolerance)
                let range = try ScalarInterval(lower: min(cell.secondStart, cell.secondEnd),
                    upper: max(cell.secondStart, cell.secondEnd))
                secondMiddle = try second.curve.closestParameterProjection(of: point,
                    options: CurveParameterProjectionOptions(parameterRange: range,
                        maximumIterations: 64, seedCount: 64, maximumSubdivisionDepth: 16,
                        maximumSubdivisionCells: 131_072, maximumCandidateCount: 4_096),
                    tolerance: tolerance).parameter
            }
            let lower = min(cell.secondStart, cell.secondEnd)
            let upper = max(cell.secondStart, cell.secondEnd)
            let margin = admission == nil
                ? max(tolerance.relative * (upper - lower),
                    Double.ulpOfOne * max(abs(cell.secondStart), abs(cell.secondEnd), 1) * 256)
                : 0
            guard firstMiddle != cell.firstStart, firstMiddle != cell.firstEnd,
                  secondMiddle > lower + margin, secondMiddle < upper - margin else {
                throw failure("Original curve coincidence could not establish a monotonic subdivision.", tolerance)
            }
            cells.append(Cell(firstStart: firstMiddle, firstEnd: cell.firstEnd,
                secondStart: secondMiddle, secondEnd: cell.secondEnd, depth: cell.depth + 1))
            cells.append(Cell(firstStart: cell.firstStart, firstEnd: firstMiddle,
                secondStart: cell.secondStart, secondEnd: secondMiddle, depth: cell.depth + 1))
        }
        return true
    }

    private func certifies(_ cell: Cell, first: Source, second: Source,
        tolerance: ModelingTolerance) throws -> Bool {
        let firstWhole = try first.jet(over: ScalarInterval(lower: min(cell.firstStart, cell.firstEnd),
            upper: max(cell.firstStart, cell.firstEnd)), tolerance: tolerance)
        let secondWhole = try second.jet(over: ScalarInterval(lower: min(cell.secondStart, cell.secondEnd),
            upper: max(cell.secondStart, cell.secondEnd)), tolerance: tolerance)
        let position = IntervalVector3DBounds(x: firstWhole.x.value - secondWhole.x.value,
            y: firstWhole.y.value - secondWhole.y.value, z: firstWhole.z.value - secondWhole.z.value)
        if position.lengthUpperBound <= tolerance.distance { return true }
        // A derivative union cannot prove the integral bound across a jump.
        guard first.continuous, second.continuous else { return false }
        let firstSpan = OutwardScalarInterval.exact(cell.firstEnd) - .exact(cell.firstStart)
        let secondSpan = OutwardScalarInterval.exact(cell.secondEnd) - .exact(cell.secondStart)
        let firstMid = OutwardScalarInterval.exact(cell.firstStart) + firstSpan * .exact(0.5)
        let secondMid = OutwardScalarInterval.exact(cell.secondStart) + secondSpan * .exact(0.5)
        let firstCenter = try first.jet(over: ScalarInterval(lower: firstMid.lower, upper: firstMid.upper), tolerance: tolerance)
        let secondCenter = try second.jet(over: ScalarInterval(lower: secondMid.lower, upper: secondMid.upper), tolerance: tolerance)
        func bound(_ a: SurfaceIntervalJet, _ b: SurfaceIntervalJet,
            _ wholeA: SurfaceIntervalJet, _ wholeB: SurfaceIntervalJet) -> OutwardScalarInterval {
            let center = a.value - b.value
            let derivative = wholeA.derivativeU * firstSpan - wholeB.derivativeU * secondSpan
            let radius = OutwardScalarInterval.exact(center.absoluteUpperBound)
                + .exact(0.5) * .exact(derivative.absoluteUpperBound)
            return .init(lower: -radius.upper, upper: radius.upper)
        }
        let residual = IntervalVector3DBounds(
            x: bound(firstCenter.x, secondCenter.x, firstWhole.x, secondWhole.x),
            y: bound(firstCenter.y, secondCenter.y, firstWhole.y, secondWhole.y),
            z: bound(firstCenter.z, secondCenter.z, firstWhole.z, secondWhole.z))
        guard residual.x.isFinite, residual.y.isFinite, residual.z.isFinite else {
            throw failure("Original coincidence residual bound is not finite.", tolerance)
        }
        return residual.lengthUpperBound <= tolerance.distance
    }

    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}
