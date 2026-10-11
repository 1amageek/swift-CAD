import CADCore
import CADGeometry
@testable import CADTopology
import HashTreeCollections

/// Actual Topology validation cancellation and retained entity audit formatting.
public enum M6TopologyPortableFixtures {
    private enum Failure: Error { case expectedCancellation,canonicalAudit,diagnostic }

    public static func verifyCanonicalAudit() throws {
        let first = VertexID(.init(high:0x0123456789ABCDEF,low:0xFEDCBA9876543210))
        let second = VertexID(.init(high:0x1111111122222222,low:0x3333333344444444))
        let third = VertexID(.init(high:0x5555555566666666,low:0x7777777788888888))
        var before = BRepModel()
        before.vertices[first] = Vertex(id:first,point:.origin)
        before.vertices[second] = Vertex(id:second,point:.origin)
        var after = before
        after.vertices[first] = Vertex(id:first,point:.init(x:1,y:0,z:0))
        after.vertices[second] = nil
        after.vertices[third] = Vertex(id:third,point:.origin)
        let delta = BRepRepairAudit().entityDelta(from:before,to:after)
        let changed = "vertex:01234567-89AB-CDEF-FEDC-BA9876543210"
        let deleted = "vertex:11111111-2222-2222-3333-333344444444"
        let generated = "vertex:55555555-6666-6666-7777-777788888888"
        guard delta.affected == [changed,deleted,generated],delta.deleted == [deleted],delta.generated == [generated] else {
            throw Failure.canonicalAudit
        }
        print("PASS M6 canonical Topology changed/generated/deleted audit IDs")
    }

    public static func verifyDiagnosticAuthority() throws {
        let model = BRepModel(),bad = ModelingTolerance(distance:-2,angle:0.25,relative:0.5)
        let expected = GeometryError.invalidModelingTolerance(distance:-2,angle:0.25,relative:0.5)
        do {
            _ = try DefaultBRepTopologyValidator().report(for:model,request:.all,tolerance:bad)
            throw Failure.diagnostic
        } catch let error as GeometryError {
            guard error == expected else { throw Failure.diagnostic }
        }
        let report = model.diagnose(tolerance:bad)
        guard !report.isValid,report.diagnostics.count == 1,
            report.diagnostics[0].code == .invalidInput,
            report.diagnostics[0].message == KernelError.wrapping(expected,phase:.topology,tolerance:bad).message else {
            throw Failure.diagnostic
        }
        do {
            _ = try DefaultBRepTopologyValidator().report(for:model,request:.init(scopes:[]),tolerance:.standard)
            throw Failure.diagnostic
        } catch let error as KernelError {
            guard error.message == "A B-rep validation request requires unique non-empty scopes.",
                KernelError.wrapping(error,phase:.topology,tolerance:.standard).message == error.message else {
                throw Failure.diagnostic
            }
        }
        let invalid = Point3D(x:.infinity,y:0,z:0)
        let coordinateError = GeometryError.invalidCoordinate(.infinity)
        let vertex = Vertex(point:invalid)
        let coordinateModel = BRepModel(vertices:[vertex.id:vertex])
        let coordinateReport = try DefaultBRepTopologyValidator().report(for:coordinateModel,
            request:.init(scopes:[.references]),tolerance:.standard)
        let text = "Vertex contains an invalid coordinate: "
            + KernelError.wrapping(coordinateError,phase:.topology,tolerance:.standard).message + "."
        guard !coordinateReport.isValid,coordinateReport.diagnostics.contains(where:{
            $0.code == .invalidInput && $0.message == text
        }) else { throw Failure.diagnostic }
        let topologyError = TopologyError.missingReference("M6 retained topology reference")
        let topologyPresentation = KernelError.wrapping(topologyError,phase:.topology,tolerance:.standard)
        guard topologyPresentation.code == .missingReference,!topologyPresentation.message.isEmpty else {
            throw Failure.diagnostic
        }
#if !hasFeature(Embedded)
        guard topologyPresentation.message == String(describing:topologyError),
            text == "Vertex contains an invalid coordinate: " + String(describing:coordinateError) + "." else {
            throw Failure.diagnostic
        }
#endif
        print("PASS M6 actual Topology invalid tolerance payload and retained KernelError/GeometryError/TopologyError diagnostic authority")
    }

    public static func verifyDefaultArcLengthOptions() throws {
        let curveID = CurveID(),start = Vertex(point:.origin),end = Vertex(point:.init(x:3,y:0,z:0))
        let curve = Curve3D.line(Line3D(origin:.origin,direction:.unitX))
        let edge = Edge(curveID:curveID,startVertexID:start.id,endVertexID:end.id)
        let model = BRepModel(geometry:GeometryStore(curves:[curveID:curve]),
            edges:[edge.id:edge],vertices:[start.id:start,end.id:end])
        let actual = try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(of:edge,in:model,tolerance:.standard)
        let expected = try DefaultCurveArcLengthResolver().enclosure(of:curve,
            over:ScalarInterval(lower:0,upper:3),options:CurveArcLengthOptions(),tolerance:.standard)
        guard actual == expected,actual.lowerBound <= 3,actual.upperBound >= 3 else {
            throw Failure.diagnostic
        }
        print("PASS M6 actual edge arc length dispatch retains default options")
    }

    public static func verifyCurrentTaskCancellation() async throws {
        let model = try M6ExactBoundaryFixtures.face(M6ExactBoundaryFixtures.plane(),[(.outer,M6ExactBoundaryFixtures.rectangle())]).0.model
        let task = Task {
            try withUnsafeCurrentTask { current in
                guard let current else { throw Failure.expectedCancellation }
                current.cancel()
            }
            do {
                _ = try ValidatedBRepModel(model,tolerance:.standard,validationLevel:.exact)
                throw Failure.expectedCancellation
            } catch is CancellationError {
                // The actual public exact validator preserves current-task cancellation.
            }
        }
        try await task.value
        print("PASS M6 actual exact Topology validator current-task cancellation")
    }
}
