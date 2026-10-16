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

/// Original cofactor and signed chart transport, preserving each source image layer.
package struct OriginalImagePoleNormalTransport: Sendable {
    package init() {}

    /// Preserves the original model normal without evaluating a rounded foreign station.
    package func normal(source: OriginalSurfacePoleNormalReceipt, image: OriginalImageSurface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OriginalSurfacePoleNormalReceipt {
        try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
        guard source.surface == image.source, source.tolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Original image normal belongs to another source or tolerance.")
        }
        try image.validate(tolerance: tolerance, using: &execution)
        _ = try image.transform.originalDeterminantSign(using: &execution)
        func original(_ vector: Vector3D) -> IntervalVector3DBounds {
            .init(x: .exact(vector.x), y: .exact(vector.y), z: .exact(vector.z))
        }
        let a = original(image.transform.basisX), b = original(image.transform.basisY), c = original(image.transform.basisZ)
        let uSign = image.uParameterGain.coefficients.numerator > 0 ? 1.0 : -1.0
        let vSign = image.vParameterGain.coefficients.numerator > 0 ? 1.0 : -1.0
        let parity = uSign * vSign * (image.swapAxes ? -1.0 : 1.0)
        let field = (b.cross(c) * source.coefficientBounds.x + c.cross(a) * source.coefficientBounds.y
            + a.cross(b) * source.coefficientBounds.z) * .exact(parity)
        let lower = field.lengthLowerBound, upper = field.lengthUpperBound
        let representative = field.midpoint, length = representative.length
        guard lower.isFinite, lower > 0, upper.isFinite, length.isFinite, length > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original image pole normal has no finite nonzero coefficient cone.")
        }
        let normal = representative / length
        let magnitude = OutwardScalarInterval(lower: lower, upper: upper)
        guard let x = field.x.divided(by: magnitude), let y = field.y.divided(by: magnitude),
              let z = field.z.divided(by: magnitude) else {
            throw GeometryConversionError.resourceLimitExceeded("Original image normal cone cannot be normalized.")
        }
        let spread = IntervalVector3DBounds(x: x - .exact(normal.x), y: y - .exact(normal.y),
            z: z - .exact(normal.z)).lengthUpperBound
        let angle = (2 * asin(min(1, spread / 2))).nextUp
        guard angle.isFinite, angle <= tolerance.angle else {
            throw KernelError(phase: .geometry, code: .approximationToleranceRejected,
                tolerance: tolerance, message: "Original image pole normal cone exceeds the supplied angular tolerance.")
        }
        let nativeU = image.swapAxes ? source.parameters.v : source.parameters.u
        let nativeV = image.swapAxes ? source.parameters.u : source.parameters.v
        let parameters = try SurfaceParameterBox(
            u: OriginalParameterImageMap.inverseInterval(nativeU, gain: image.uParameterGain, offset: image.uOffset, usage: &execution),
            v: OriginalParameterImageMap.inverseInterval(nativeV, gain: image.vParameterGain, offset: image.vOffset, usage: &execution))
        return .init(surface: .parameterImage(image), parameters: parameters, normal: normal,
            angularDeviationUpperBound: angle, coefficientBounds: field, tolerance: tolerance)
    }

    /// Transports whole original normal derivatives, including source pole factors.
    package func differentialBounds(_ b: SurfaceTessellationDifferentialBounds,
        through image: OriginalImageSurface3D, using execution: inout OriginalQueryExecution)
        throws -> SurfaceTessellationDifferentialBounds {
        try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
        _ = try image.transform.originalDeterminantSign(using: &execution)
        func original(_ column: Vector3D) -> IntervalVector3DBounds {
            .init(x: .exact(column.x), y: .exact(column.y), z: .exact(column.z))
        }
        let x = original(image.transform.basisX), y = original(image.transform.basisY), z = original(image.transform.basisZ)
        let bx = y.cross(z), by = z.cross(x), bz = x.cross(y)
        let determinant = x.dot(bx)
        guard determinant.isFinite, determinant.excludesZero else {
            throw GeometryConversionError.resourceLimitExceeded("Original pole image needs a finite nonsingular affine inverse enclosure.")
        }
        let affineNorm = (x.lengthUpperBound + y.lengthUpperBound + z.lengthUpperBound).nextUp
        let cofactorNorm = (bx.lengthUpperBound + by.lengthUpperBound + bz.lengthUpperBound).nextUp
        let lower = min(abs(determinant.lower), abs(determinant.upper))
        let condition = (cofactorNorm * (affineNorm / lower).nextUp).nextUp
        let u = try image.uParameterGain.interval(), v = try image.vParameterGain.interval()
        let us = max(abs(u.lower), abs(u.upper)), vs = max(abs(v.lower), abs(v.upper))
        let fields = [
            (affineNorm * us * (image.swapAxes ? b.tangentVMagnitudeUpperBound : b.tangentUMagnitudeUpperBound)).nextUp,
            (affineNorm * vs * (image.swapAxes ? b.tangentUMagnitudeUpperBound : b.tangentVMagnitudeUpperBound)).nextUp,
            (affineNorm * us * us * (image.swapAxes ? b.secondDerivativeVVMagnitudeUpperBound : b.secondDerivativeUUMagnitudeUpperBound)).nextUp,
            (affineNorm * us * vs * b.secondDerivativeUVMagnitudeUpperBound).nextUp,
            (affineNorm * vs * vs * (image.swapAxes ? b.secondDerivativeUUMagnitudeUpperBound : b.secondDerivativeVVMagnitudeUpperBound)).nextUp,
            (condition * us * (image.swapAxes ? b.unitNormalDerivativeVMagnitudeUpperBound : b.unitNormalDerivativeUMagnitudeUpperBound)).nextUp,
            (condition * vs * (image.swapAxes ? b.unitNormalDerivativeUMagnitudeUpperBound : b.unitNormalDerivativeVMagnitudeUpperBound)).nextUp]
        guard fields.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw GeometryConversionError.resourceLimitExceeded("Original transported pole differential fields exceed finite bounds.")
        }
        return .init(tangentUMagnitudeUpperBound: fields[0], tangentVMagnitudeUpperBound: fields[1],
            secondDerivativeUUMagnitudeUpperBound: fields[2], secondDerivativeUVMagnitudeUpperBound: fields[3],
            secondDerivativeVVMagnitudeUpperBound: fields[4], unitNormalDerivativeUMagnitudeUpperBound: fields[5],
            unitNormalDerivativeVMagnitudeUpperBound: fields[6])
    }

    package func panelBounds(source: OriginalSurfacePoleNormalPanel, image: OriginalImageSurface3D,
        over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> OriginalSurfacePoleNormalPanel {
        try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
        guard source.surface == image.source, source.tolerance == tolerance else {
            throw GeometryConversionError.invalidInput("Original pole image receipt belongs to another source or tolerance.")
        }
        try image.validate(tolerance: tolerance, using: &execution)
        let native = try image.sourceParameterBounds(over: parameters, tolerance: tolerance, using: &execution)
        guard native.u.lower >= source.parameters.u.lower, native.u.upper <= source.parameters.u.upper,
              native.v.lower >= source.parameters.v.lower, native.v.upper <= source.parameters.v.upper else {
            throw GeometryConversionError.invalidInput("Original image pole query exceeds its retained source panel.")
        }
        _ = try image.transform.originalDeterminantSign(using: &execution)
        func original(_ column: Vector3D) -> IntervalVector3DBounds {
            .init(x: .exact(column.x), y: .exact(column.y), z: .exact(column.z))
        }
        let x = original(image.transform.basisX), y = original(image.transform.basisY), z = original(image.transform.basisZ)
        try execution.consumeWork(1)
        let bx = y.cross(z), by = z.cross(x), bz = x.cross(y)
        let determinant = x.dot(bx)
        guard determinant.excludesZero, determinant.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original affine pole transport has no finite inverse interval authority.")
        }
        let determinantLower = min(abs(determinant.lower), abs(determinant.upper))
        let affineNorm = (x.lengthUpperBound + y.lengthUpperBound + z.lengthUpperBound).nextUp
        let cofactorNorm = (bx.lengthUpperBound + by.lengthUpperBound + bz.lengthUpperBound).nextUp
        let inverseCofactorNorm = (affineNorm / determinantLower).nextUp
        let condition = (cofactorNorm * inverseCofactorNorm).nextUp
        guard affineNorm.isFinite, condition.isFinite, condition > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original affine pole condition bounds are nonfinite.")
        }
        let u = try image.uParameterGain.interval(), v = try image.vParameterGain.interval()
        let uScale = max(abs(u.lower), abs(u.upper)), vScale = max(abs(v.lower), abs(v.upper))
        let parity = (u.lower > 0 ? 1.0 : -1.0) * (v.lower > 0 ? 1.0 : -1.0)
            * (image.swapAxes ? -1.0 : 1.0)
        let field = (bx * source.normalField.x + by * source.normalField.y + bz * source.normalField.z) * .exact(parity)
        guard field.lengthLowerBound > 0, field.lengthUpperBound.isFinite else {
            throw GeometryConversionError.resourceLimitExceeded("Original transported pole normal field is not certified nonzero.")
        }
        let b = source.differentialBounds
        let bounds = SurfaceTessellationDifferentialBounds(
            tangentUMagnitudeUpperBound: (affineNorm * uScale
                * (image.swapAxes ? b.tangentVMagnitudeUpperBound : b.tangentUMagnitudeUpperBound)).nextUp,
            tangentVMagnitudeUpperBound: (affineNorm * vScale
                * (image.swapAxes ? b.tangentUMagnitudeUpperBound : b.tangentVMagnitudeUpperBound)).nextUp,
            secondDerivativeUUMagnitudeUpperBound: (affineNorm * uScale * uScale
                * (image.swapAxes ? b.secondDerivativeVVMagnitudeUpperBound : b.secondDerivativeUUMagnitudeUpperBound)).nextUp,
            secondDerivativeUVMagnitudeUpperBound: (affineNorm * uScale * vScale * b.secondDerivativeUVMagnitudeUpperBound).nextUp,
            secondDerivativeVVMagnitudeUpperBound: (affineNorm * vScale * vScale
                * (image.swapAxes ? b.secondDerivativeUUMagnitudeUpperBound : b.secondDerivativeVVMagnitudeUpperBound)).nextUp,
            unitNormalDerivativeUMagnitudeUpperBound: (condition * uScale
                * (image.swapAxes ? b.unitNormalDerivativeVMagnitudeUpperBound : b.unitNormalDerivativeUMagnitudeUpperBound)).nextUp,
            unitNormalDerivativeVMagnitudeUpperBound: (condition * vScale
                * (image.swapAxes ? b.unitNormalDerivativeUMagnitudeUpperBound : b.unitNormalDerivativeVMagnitudeUpperBound)).nextUp)
        return .init(surface: .parameterImage(image), parameters: parameters, normalField: field,
            tolerance: tolerance, differentialBounds: bounds)
    }
}
