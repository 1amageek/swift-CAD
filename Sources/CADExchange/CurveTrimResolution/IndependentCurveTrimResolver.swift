import Foundation
import CADCore
import CADGeometry

struct IndependentCurveTrimResolver {
    func parameter(of point: Point3D, on curve: Curve3D, tolerance: ModelingTolerance,
                   usage: IndependentShapeExchangeOwner, depth: Int = 0, using execution: inout OriginalQueryExecution) throws -> Double {
        guard depth < usage.limits.maximumNesting else { throw IndependentShapeExchangeError.resourceLimitExceeded("Cartesian trim image depth.") }
        try execution.admitSourceDepth(depth)
        try execution.consumeWork(1)
        let parameter: Double
        switch curve {
        case .parameterImage(let image):
            let native = try self.parameter(of: point, on: image.source, tolerance: tolerance, usage: usage, depth: depth + 1, using: &execution)
            parameter = try image.foreignParameter(fromSourceParameter: native, tolerance: tolerance, using: &execution)
        case .affineImage(let image):
            if case .line(let line) = image.source {
                let origin = image.transform.applying(to: line.origin)
                let direction = image.transform.applying(to: line.direction)
                let scale = max(abs(direction.x), abs(direction.y), abs(direction.z))
                guard scale.isFinite, scale > 0 else { throw IndependentShapeExchangeError.invalidAssociation("Collapsed Cartesian trim line.") }
                let normalized = direction / scale
                let value = (point - origin).dot(normalized) / normalized.dot(normalized) / scale
                let actual = try curve.point(at: value, tolerance: tolerance, using: &execution)
                guard value.isFinite, (actual - point).length <= tolerance.distance else { throw IndependentShapeExchangeError.invalidAssociation("Cartesian selector is off its affine line.") }
                try usage.check()
                return value
            }
            let local = try IndependentOriginalAffineInverse().point(point, through: image.transform, usage: usage, using: &execution)
            parameter = try self.parameter(of: local, on: image.source, tolerance: tolerance, usage: usage, depth: depth + 1, using: &execution)
        case .rigidImage(let image):
            parameter = try self.parameter(of: image.transform.inverted().applying(to: point), on: image.source,
                tolerance: tolerance, usage: usage, depth: depth + 1, using: &execution)
        case .bSpline(let spline):
            let order = spline.degree + 1
            let product = order.multipliedReportingOverflow(by: order)
            let next = product.partialValue.multipliedReportingOverflow(by: order)
            let cost = next.partialValue.multipliedReportingOverflow(by: 512)
            guard !product.overflow, !next.overflow, !cost.overflow, cost.partialValue > 0 else {
                throw IndependentShapeExchangeError.resourceLimitExceeded("Cartesian spline inverse work overflow.")
            }
            let remaining = usage.limits.maximumIterations - usage.consumedWork
            let preparation = spline.controlPoints.count.multipliedReportingOverflow(by: cost.partialValue)
            guard !preparation.overflow, preparation.partialValue < remaining else { throw IndependentShapeExchangeError.resourceLimitExceeded("Cartesian spline preparation allowance.") }
            let cells = min(1_048_576, (remaining - preparation.partialValue) / cost.partialValue / 2, (usage.limits.maximumEntities - usage.consumedEntities) / 3)
            guard cells > 0 else { throw IndependentShapeExchangeError.resourceLimitExceeded("No Cartesian spline inverse allowance.") }
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
            let options = CurveParameterProjectionOptions(maximumIterations: 256, seedCount: 2,
                maximumSubdivisionDepth: usage.limits.maximumCurveSubdivisionDepth,
                maximumSubdivisionCells: cells, maximumCandidateCount: min(cells, 65_536))
            parameter = try curve.parameterProjection(of: point, options: options, tolerance: tolerance, using: &execution).parameter
        default:
            parameter = try curve.parameterProjection(of: point, tolerance: tolerance, using: &execution).parameter
        }
        try usage.check()
        let actual = try curve.point(at: parameter, tolerance: tolerance, using: &execution)
        guard parameter.isFinite, (actual - point).length <= tolerance.distance else {
            throw IndependentShapeExchangeError.invalidAssociation("Cartesian trim does not correspond to its original curve law.")
        }
        return parameter
    }
}
