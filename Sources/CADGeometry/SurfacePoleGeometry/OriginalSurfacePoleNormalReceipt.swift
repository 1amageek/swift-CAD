import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Original normal cone with retained source station intervals for nested chart images.
package struct OriginalSurfacePoleNormalReceipt: Sendable {
    package let surface: Surface3D
    package let parameters: SurfaceParameterBox
    package let normal: Vector3D
    package let angularDeviationUpperBound: Double
    package let coefficientBounds: IntervalVector3DBounds
    package let tolerance: ModelingTolerance

    package init(native: OriginalBSplinePoleNormalReceipt) throws {
        surface = .bSpline(native.surface)
        parameters = try .init(u: ScalarInterval(lower: native.parameter.u, upper: native.parameter.u),
            v: ScalarInterval(lower: native.parameter.v, upper: native.parameter.v))
        normal = native.normal; angularDeviationUpperBound = native.angularDeviationUpperBound
        coefficientBounds = native.coefficientBounds; tolerance = native.tolerance
    }

    /// Normalizes the complete original station box, never a midpoint station.
    package init(panel: OriginalSurfacePoleNormalPanel) throws {
        let field = panel.normalField, lower = field.lengthLowerBound, upper = field.lengthUpperBound
        let representative = field.midpoint, length = representative.length
        guard lower.isFinite, lower > 0, upper.isFinite, length.isFinite, length > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original pole station box has no nonzero finite normal field.")
        }
        let direction = representative / length
        let magnitude = OutwardScalarInterval(lower: lower, upper: upper)
        guard let x = field.x.divided(by: magnitude), let y = field.y.divided(by: magnitude),
              let z = field.z.divided(by: magnitude) else {
            throw GeometryConversionError.resourceLimitExceeded("Original pole station cone cannot be normalized.")
        }
        let spread = IntervalVector3DBounds(x: x - .exact(direction.x), y: y - .exact(direction.y),
            z: z - .exact(direction.z)).lengthUpperBound
        let angle = (2 * asin(min(1, spread / 2))).nextUp
        guard angle.isFinite, angle <= panel.tolerance.angle else {
            throw KernelError(phase: .geometry, code: .approximationToleranceRejected,
                tolerance: panel.tolerance, message: "Original whole pole station cone exceeds its angular allowance.")
        }
        self.init(surface: panel.surface, parameters: panel.parameters, normal: direction,
            angularDeviationUpperBound: angle, coefficientBounds: field, tolerance: panel.tolerance)
    }

    /// Complete source-owning coverage of a closed station across native joins.
    package init(panels:[OriginalSurfacePoleNormalPanel],over requested:SurfaceParameterBox,
        consumeWork:()throws->Void) throws {
        guard let first = panels.first else {
            throw GeometryConversionError.invalidInput("Original pole normal coverage is empty.")
        }
        let alongV = requested.u.width == 0
        guard alongV || requested.v.width == 0 else {
            throw GeometryConversionError.invalidInput("Original joined pole receipt needs one collapsed coordinate.")
        }
        let target = alongV ? requested.v : requested.u
        for panel in panels {
            try consumeWork()
            let fixed = alongV ? panel.parameters.u : panel.parameters.v
            let targetFixed = alongV ? requested.u : requested.v
            let interval = alongV ? panel.parameters.v : panel.parameters.u
            guard panel.surface == first.surface,panel.tolerance == first.tolerance,fixed == targetFixed,
                  interval.lower >= target.lower,interval.upper <= target.upper else {
                throw GeometryConversionError.invalidInput("Original pole panel coverage has a different source or station binding.")
            }
        }
        let sortLevels = panels.count <= 1 ? 0 : Int.bitWidth-(panels.count-1).leadingZeroBitCount
        for _ in 0..<panels.count*(sortLevels+1) { try consumeWork() }
        let ordered = panels.sorted {
            (alongV ? $0.parameters.v.lower : $0.parameters.u.lower) <
            (alongV ? $1.parameters.v.lower : $1.parameters.u.lower)
        }
        var covered = target.lower
        var field:IntervalVector3DBounds?
        for panel in ordered {
            try consumeWork()
            let interval = alongV ? panel.parameters.v : panel.parameters.u
            guard interval.lower <= covered else {
                throw GeometryConversionError.invalidInput("Original pole station coverage leaves a native parameter gap.")
            }
            covered = max(covered,interval.upper)
            let bounds = panel.normalField
            let length = OutwardScalarInterval(lower:bounds.lengthLowerBound,upper:bounds.lengthUpperBound)
            guard length.lower > 0,let x = bounds.x.divided(by:length),let y = bounds.y.divided(by:length),
                  let z = bounds.z.divided(by:length) else {
                throw GeometryConversionError.resourceLimitExceeded("An original owning normal field has no nonzero normalization.")
            }
            let unit = IntervalVector3DBounds(x:x,y:y,z:z)
            if let prior = field {
                field = .init(x:.init(lower:min(prior.x.lower,x.lower),upper:max(prior.x.upper,x.upper)),
                    y:.init(lower:min(prior.y.lower,y.lower),upper:max(prior.y.upper,y.upper)),
                    z:.init(lower:min(prior.z.lower,z.lower),upper:max(prior.z.upper,z.upper)))
            } else { field = unit }
        }
        guard covered == target.upper,let field else {
            throw GeometryConversionError.invalidInput("Original pole station coverage is incomplete.")
        }
        // Derivative bounds are deliberately not published by this station
        // receipt: one-sided coverage proves a cone, not join smoothness.
        try self.init(panel:.init(surface:first.surface,parameters:requested,normalField:field,
            tolerance:first.tolerance,differentialBounds:first.differentialBounds))
    }

    /// Exact word cofactor acts on the complete original station cone.
    package func transformed<B: RationalAlgebraAdmitting>(through image: OriginalAffineWordSurface3D,
        tolerance: ModelingTolerance, usage: inout B) throws -> Self {
        try GeometryStructuralComparisonWork.charge(surface: surface, using: { try usage.consumeExactWork($0) })
        try GeometryStructuralComparisonWork.charge(surface: image.source, using: { try usage.consumeExactWork($0) })
        guard surface == image.source, self.tolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Original word normal has a different source or tolerance binding.")
        }
        let input = try CoordinateEnclosure3D(x: .init(lower: coefficientBounds.x.lower, upper: coefficientBounds.x.upper),
            y: .init(lower: coefficientBounds.y.lower, upper: coefficientBounds.y.upper),
            z: .init(lower: coefficientBounds.z.lower, upper: coefficientBounds.z.upper))
        let q = try image.preparedWord.applyingCofactor(to: input, usage: &usage)
        let field = IntervalVector3DBounds(x: .init(lower: q.x.lower, upper: q.x.upper),
            y: .init(lower: q.y.lower, upper: q.y.upper), z: .init(lower: q.z.lower, upper: q.z.upper))
        let lower = field.lengthLowerBound, upper = field.lengthUpperBound
        let representative = field.midpoint, length = representative.length
        guard lower.isFinite, lower > 0, upper.isFinite, length.isFinite, length > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original word pole cone has no finite positive normal bound.")
        }
        let direction = representative / length
        let magnitude = OutwardScalarInterval(lower: lower, upper: upper)
        guard let x = field.x.divided(by: magnitude), let y = field.y.divided(by: magnitude),
            let z = field.z.divided(by: magnitude) else {
            throw GeometryConversionError.resourceLimitExceeded("Original word pole cone normalization is nonfinite.")
        }
        let spread = IntervalVector3DBounds(x: x - .exact(direction.x), y: y - .exact(direction.y),
            z: z - .exact(direction.z)).lengthUpperBound
        let angle = (2 * asin(min(1, spread / 2))).nextUp
        guard angle.isFinite, angle <= tolerance.angle else {
            throw KernelError(phase: .geometry, code: .approximationToleranceRejected, tolerance: tolerance,
                message: "Original word pole cone exceeds its original angular allowance.")
        }
        return .init(surface: .procedural(.originalAffineWord(image)), parameters: parameters,
            normal: direction, angularDeviationUpperBound: angle, coefficientBounds: field, tolerance: tolerance)
    }

    init(surface: Surface3D, parameters: SurfaceParameterBox, normal: Vector3D,
        angularDeviationUpperBound: Double, coefficientBounds: IntervalVector3DBounds, tolerance: ModelingTolerance) {
        self.surface = surface; self.parameters = parameters; self.normal = normal
        self.angularDeviationUpperBound = angularDeviationUpperBound
        self.coefficientBounds = coefficientBounds; self.tolerance = tolerance
    }
}
