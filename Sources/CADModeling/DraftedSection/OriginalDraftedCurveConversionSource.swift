import CADCore
import CADGeometry

/// Conversion adapter for the persistent original draft, without duplicated ruling math.
package struct OriginalDraftedCurveConversionSource: GeometryCurveConversionSource {
    package let source: OriginalDraftedCurve3D
    private let admission: GeometryConversionAdmission
    package init(source:OriginalDraftedCurve3D,admission:GeometryConversionAdmission) {
        self.source = source; self.admission = admission
    }
    package func validate(over parameters:ScalarInterval,tolerance:ModelingTolerance) throws {
        try admission.chargeWork(); try source.validate(tolerance:tolerance)
        guard parameters.lower >= 0, parameters.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original drafted candidate must use its retained normalized chart.")
        }
    }
    package func validate(over parameters:ScalarInterval,tolerance:ModelingTolerance,
        admission:GeometryConversionAdmission) throws {
        try admission.chargeWork(); try validate(over:parameters,tolerance:tolerance)
    }
    package func enclosure(over parameters:ScalarInterval,tolerance:ModelingTolerance)
        throws -> CurveDifferentialEnclosure {
        try validate(over:parameters,tolerance:tolerance)
        let q = try source.intervalTaylorJet(over:parameters,throughOrder:2,tolerance:tolerance,
            maximumSpanCount:admission.maximumSpanCount,maximumSubdivisionDepth:admission.maximumSubdivisionDepth,
            remainingSourceDepth:admission.remainingSourceDepth,consumeWork:{ try admission.chargeWork() },
            consumeStorage:{ try admission.chargeStorage(bytes:$0) })
        func field(_ order:Int) throws -> CoordinateEnclosure3D {
            let scale = OutwardScalarInterval.exact(order == 2 ? 2 : 1)
            let x = try q.x.coefficient(order,0)*scale,y = try q.y.coefficient(order,0)*scale,z = try q.z.coefficient(order,0)*scale
            return try .init(x:.init(lower:x.lower,upper:x.upper),y:.init(lower:y.lower,upper:y.upper),z:.init(lower:z.lower,upper:z.upper))
        }
        return try .init(position:field(0),firstDerivative:field(1),secondDerivative:field(2))
    }
    package func enclosure(over parameters:ScalarInterval,tolerance:ModelingTolerance,
        admission:GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        try admission.chargeWork(); return try enclosure(over:parameters,tolerance:tolerance)
    }
    package func pointAndDerivative(at parameter:Double,tolerance:ModelingTolerance)
        throws -> (point:Point3D,derivative:Vector3D) {
        let e = try enclosure(over:.init(lower:parameter,upper:parameter),tolerance:tolerance)
        return (.init(x:e.position.x.midpoint,y:e.position.y.midpoint,z:e.position.z.midpoint),
            .init(x:e.firstDerivative.x.midpoint,y:e.firstDerivative.y.midpoint,z:e.firstDerivative.z.midpoint))
    }
}
