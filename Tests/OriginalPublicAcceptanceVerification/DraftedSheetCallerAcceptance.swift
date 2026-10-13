import CADCore
import HashTreeCollections
import CADGeometry
import CADIR
import CADTopology
import CADModeling
import CADKernel

/// Runs both actual original-sheet publication branches with the authored nonzero angle.
@main struct DraftedSheetCallerAcceptance {
    static func require(_ value:Bool) throws { guard value else { throw ExactScalarFailure.invalidEvidence } }
    static func main() throws {
        let id=FeatureID()
        let curve=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:0,z:0)],weights:[1,2])
        let section=EvaluatedCurve(sourceFeatureID:id,source:.generatedFeature,kind:.spline,
            points:[.origin,.init(x:1,y:0,z:0)],plane:.xy,exactCurve:.bSpline(curve),
            exactParameterDomain:.closed(0,1),exactPointParameters:[0,1])
        let feature=FeatureNode(operation:.extrude(.init(section:.curve(.init(featureID:id)),
            distance:.constant(.length(2,unit:.meter)),direction:.vector(.unitZ),resultKind:.sheet,
            draftAngle:.constant(.angle(1e-12,unit:.radian)))),
            inputs:[.init(featureID:id,role:.curve)],outputs:[.init(role:.sheet)])
        let context=EvaluationContext(parameters:.init(),brep:.init(),profiles:[:],curves:[id:[section]],tolerance:.standard)
        for supplied in [false,true] {
            let evaluator=PlanarExtrudeFeatureEvaluator(sewer:DefaultBRepSewer(),
                generatedResultValidator:supplied ? DefaultOffsetResultValidator():nil)
            let result=try evaluator.evaluate(feature:feature,context:context)
            try require(result.brep.bodies.count==1 && result.brep.faces.count==1)
            guard let face=result.brep.faces.values.first,
                case .procedural(.originalDrafted(let wall))?=result.brep.geometry.surfaces[face.surfaceID] else {
                throw ExactScalarFailure.invalidEvidence
            }
            try require(wall.start.angle==1e-12 && wall.start.height==0 && wall.endHeight==2)
            for (u,v) in [(0.0,0.0),(0.25,0.5),(1.0,1.0)] {
                let point=try wall.point(u:u,v:v,tolerance:.standard)
                try require(abs(point.x-2*u/(1+u))<=1e-12 && abs(point.z-2*v)<=1e-12)
                if v>0 { try require(point.y>0) }
            }
            print(supplied ? "PASS actual drafted sheet with DefaultOffsetResultValidator":"PASS actual drafted sheet standalone receipt session")
        }
    }
}
