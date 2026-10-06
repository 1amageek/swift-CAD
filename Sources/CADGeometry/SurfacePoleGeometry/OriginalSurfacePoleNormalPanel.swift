import CADCore

/// Original factored normal field with whole parameter-panel derivative authority.
package struct OriginalSurfacePoleNormalPanel: Sendable {
    package let surface: Surface3D
    package let parameters: SurfaceParameterBox
    package let normalField: IntervalVector3DBounds
    package let tolerance: ModelingTolerance
    package let differentialBounds: SurfaceTessellationDifferentialBounds

    package init(native: OriginalBSplinePoleNormalPanel) {
        surface = .bSpline(native.surface)
        parameters = native.parameters
        normalField = native.factorBounds
        tolerance = native.tolerance
        differentialBounds = native.differentialBounds
    }

    init(surface: Surface3D, parameters: SurfaceParameterBox, normalField: IntervalVector3DBounds,
        tolerance: ModelingTolerance, differentialBounds: SurfaceTessellationDifferentialBounds) {
        self.surface = surface; self.parameters = parameters; self.normalField = normalField
        self.tolerance = tolerance; self.differentialBounds = differentialBounds
    }

    package func union(_ other:Self) throws -> Self {
        guard surface == other.surface,parameters == other.parameters,tolerance == other.tolerance else {
            throw GeometryConversionError.invalidInput("Original normal panel union requires the same source, closed station box and tolerance.")
        }
        func scalar(_ a:OutwardScalarInterval,_ b:OutwardScalarInterval)->OutwardScalarInterval {
            .init(lower:min(a.lower,b.lower),upper:max(a.upper,b.upper))
        }
        let a = differentialBounds,b = other.differentialBounds
        return .init(surface:surface,parameters:parameters,
            normalField:.init(x:scalar(normalField.x,other.normalField.x),y:scalar(normalField.y,other.normalField.y),z:scalar(normalField.z,other.normalField.z)),tolerance:tolerance,
            differentialBounds:.init(tangentUMagnitudeUpperBound:max(a.tangentUMagnitudeUpperBound,b.tangentUMagnitudeUpperBound),
                tangentVMagnitudeUpperBound:max(a.tangentVMagnitudeUpperBound,b.tangentVMagnitudeUpperBound),
                secondDerivativeUUMagnitudeUpperBound:max(a.secondDerivativeUUMagnitudeUpperBound,b.secondDerivativeUUMagnitudeUpperBound),
                secondDerivativeUVMagnitudeUpperBound:max(a.secondDerivativeUVMagnitudeUpperBound,b.secondDerivativeUVMagnitudeUpperBound),
                secondDerivativeVVMagnitudeUpperBound:max(a.secondDerivativeVVMagnitudeUpperBound,b.secondDerivativeVVMagnitudeUpperBound),
                unitNormalDerivativeUMagnitudeUpperBound:max(a.unitNormalDerivativeUMagnitudeUpperBound,b.unitNormalDerivativeUMagnitudeUpperBound),
                unitNormalDerivativeVMagnitudeUpperBound:max(a.unitNormalDerivativeVMagnitudeUpperBound,b.unitNormalDerivativeVMagnitudeUpperBound)))
    }

}
