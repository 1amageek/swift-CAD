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

/// Complete original analytic normal laws independent of collapsed angular metrics.
package struct OriginalAnalyticPoleNormal {
    package init() {}

    package enum ConeNappe: Sendable, Equatable { case positive, negative }

    package func panelBounds(of surface:Surface3D,over box:SurfaceParameterBox,
        coneNappe: ConeNappe? = nil, tolerance:ModelingTolerance,
        consumeWork:()throws->Void) throws -> OriginalSurfacePoleNormalPanel? {
        guard case .analytic(let analytic) = surface,
              let differential = try tessellationBounds(of:surface,over:box,tolerance:tolerance,consumeWork:consumeWork) else { return nil }
        try consumeWork()
        let encloser = DefaultSurfaceDifferentialEncloser()
        let field:IntervalVector3DBounds
        func vector(_ jet:SurfaceIntervalVectorJet,_ key:(SurfaceIntervalJet) -> OutwardScalarInterval)->IntervalVector3DBounds {
            .init(x:key(jet.x),y:key(jet.y),z:key(jet.z))
        }
        switch analytic {
        case .sphere(let center,let radius):
            guard let jet = try encloser.analyticJet(of:surface,u:.parameterU(box.u),v:.parameterV(box.v),tolerance:tolerance),
                  let inverse = OutwardScalarInterval.exact(1).divided(by:.exact(radius)) else {
                throw GeometryConversionError.resourceLimitExceeded("Original spherical radial normal is nonfinite.")
            }
            field = (vector(jet,{ $0.value }) - .init(x:.exact(center.x),y:.exact(center.y),z:.exact(center.z))) * inverse
        case .cone:
            let sign:Double
            if box.v.upper <= 0, box.v.lower < 0 { sign = -1 }
            else if box.v.lower >= 0,box.v.upper > 0 { sign = 1 }
            else if box.v.lower == 0,box.v.upper == 0,let coneNappe {
                sign = coneNappe == .positive ? 1 : -1
            } else { throw GeometryConversionError.invalidInput("Original cone apex normal needs an explicit owning nappe.") }
            if let coneNappe, (coneNappe == .positive ? sign < 0 : sign > 0) {
                throw GeometryConversionError.invalidInput("Original cone normal receipt conflicts with its owning nappe.")
            }
            guard let jet = try encloser.analyticJet(of:surface,u:.parameterU(box.u),v:.parameterV(.init(lower:1,upper:1)),tolerance:tolerance) else {
                throw GeometryConversionError.invalidInput("Original cone normal lost its coefficient law.")
            }
            field = vector(jet,{ $0.derivativeU }).cross(vector(jet,{ $0.derivativeV })) * .exact(sign)
        default: return nil
        }
        return .init(surface:surface,parameters:box,normalField:field,tolerance:tolerance,differentialBounds:differential)
    }

    package func tessellationBounds(of surface:Surface3D,over box:SurfaceParameterBox,
        tolerance:ModelingTolerance,consumeWork:()throws->Void) throws -> SurfaceTessellationDifferentialBounds? {
        guard case .analytic(let analytic) = surface else { return nil }
        let normalU:Double, normalV:Double
        let encloser = DefaultSurfaceDifferentialEncloser()
        try consumeWork(); try surface.validate(tolerance:tolerance)
        guard let jet = try encloser.analyticJet(of:surface,u:.parameterU(box.u),v:.parameterV(box.v),tolerance:tolerance) else {
            throw GeometryConversionError.invalidInput("Original analytic closed panel lost its source jet.")
        }
        func vector(_ value:SurfaceIntervalVectorJet,_ key:(SurfaceIntervalJet) -> OutwardScalarInterval)->IntervalVector3DBounds {
            .init(x:key(value.x),y:key(value.y),z:key(value.z))
        }
        switch analytic {
        case .sphere(_,let radius):
            // The original global Z frame has exact signed coordinate axes;
            // its radial expression has unit length by the sine/cosine identity.
            let inverse = OutwardScalarInterval.exact(1).divided(by:.exact(radius))
            guard let inverse else { throw GeometryConversionError.resourceLimitExceeded("Original spherical radius inverse is nonfinite.") }
            normalU = (vector(jet,{ $0.derivativeU }) * inverse).lengthUpperBound
            normalV = (vector(jet,{ $0.derivativeV }) * inverse).lengthUpperBound
        case .cone(_,let axis,let angle):
            guard box.v.lower >= 0 || box.v.upper <= 0 else {
                throw GeometryConversionError.invalidInput("Original cone normal panels must own exactly one closed nappe.")
            }
            let unitV = SurfaceIntervalJet.parameterV(try .init(lower:1,upper:1))
            guard let factoredJet = try encloser.analyticJet(of:surface,u:.parameterU(box.u),v:unitV,tolerance:tolerance) else {
                throw GeometryConversionError.invalidInput("Original cone normal factor lost its source law.")
            }
            let su = vector(factoredJet,{ $0.derivativeU }), sv = vector(factoredJet,{ $0.derivativeV })
            let derivative = vector(factoredJet,{ $0.secondDerivativeUU }).cross(sv)
                + su.cross(vector(factoredJet,{ $0.secondDerivativeUV }))
            let basis = try analyticOrthonormalBasis(axis,tolerance:tolerance)
            let bu = IntervalVector3DBounds(x:.exact(basis.u.x),y:.exact(basis.u.y),z:.exact(basis.u.z))
            let bv = IntervalVector3DBounds(x:.exact(basis.v.x),y:.exact(basis.v.y),z:.exact(basis.v.z))
            let a = IntervalVector3DBounds(x:.exact(axis.x),y:.exact(axis.y),z:.exact(axis.z))
            let sine = OutwardScalarInterval.exact(sin(angle))
            let axialProjection = bu.cross(bv).dot(a) * sine * sine * CanonicalSphereAngularPhase.scaleBounds
            let axisUpper = a.lengthUpperBound
            let lower = (axialProjection.absoluteLowerBound / axisUpper).nextDown
            guard lower.isFinite,lower > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original cone normal factor has no positive axial-projection bound.")
            }
            normalU = (derivative.lengthUpperBound/lower).nextUp
            normalV = 0
        default: return nil
        }
        let fields = [vector(jet,{ $0.derivativeU }).lengthUpperBound,vector(jet,{ $0.derivativeV }).lengthUpperBound,
            vector(jet,{ $0.secondDerivativeUU }).lengthUpperBound,vector(jet,{ $0.secondDerivativeUV }).lengthUpperBound,
            vector(jet,{ $0.secondDerivativeVV }).lengthUpperBound,normalU,normalV]
        guard fields.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw GeometryConversionError.resourceLimitExceeded("Original analytic closed normal panel exceeds finite derivative arithmetic.")
        }
        return .init(tangentUMagnitudeUpperBound:fields[0],tangentVMagnitudeUpperBound:fields[1],
            secondDerivativeUUMagnitudeUpperBound:fields[2],secondDerivativeUVMagnitudeUpperBound:fields[3],secondDerivativeVVMagnitudeUpperBound:fields[4],
            unitNormalDerivativeUMagnitudeUpperBound:fields[5],unitNormalDerivativeVMagnitudeUpperBound:fields[6])
    }
}
