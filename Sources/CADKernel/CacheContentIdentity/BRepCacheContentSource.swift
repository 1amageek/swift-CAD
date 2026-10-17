import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections

/// Canonical original content, independent of regenerated topology identifiers.
struct BRepCacheContentSource: PortableSourceEncodable {
    private enum Kind {
        case model
        case body(Body)
        case component(SolidShellComponent)
        case shell(Shell)
        case face(Face)
        case loop(Loop)
        case coedge(Coedge)
    }

    private let model: BRepModel
    private let kind: Kind

    init(model: BRepModel) { self.model = model; kind = .model }
    private init(model: BRepModel, kind: Kind) { self.model = model; self.kind = kind }

    private func children<C: Collection, A: NumericWorkAdmission & ~Copyable>(_ values: C, encoder: inout PortableSourceEncoder,
                                        using admission: inout A,
                                        kind: (C.Element) throws -> Kind) throws -> [Self] {
        let size = values.count.multipliedReportingOverflow(by: MemoryLayout<Self>.stride)
        guard !size.overflow else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Cache content child storage.")
        }
        try encoder.charge(bytes: size.partialValue, work: values.count, using: &admission)
        var output: [Self] = []
        output.reserveCapacity(values.count)
        for value in values {
            try encoder.charge(work: 1, using: &admission)
            output.append(Self(model: model, kind: try kind(value)))
        }
        return output
    }

    private func shell(_ id: ShellID) throws -> Shell {
        guard let value = model.shells[id] else { throw TopologyError.missingReference("Cache content shell is absent.") }
        return value
    }

    func encodeSource<A: NumericWorkAdmission & ~Copyable>(
        to encoder: inout PortableSourceEncoder, using admission: inout A
    ) throws {
        switch kind {
        case .model:
            let bodies = try children(model.bodies.values, encoder: &encoder, using: &admission, kind: Kind.body)
            let ordered = try encoder.canonicalOrder(bodies, using: &admission)
            try encoder.record("CADKernel.BRepCacheContent", fields: 1, using: &admission)
            try encoder.field("bodies", ordered, using: &admission)
        case .body(let body):
            try encoder.record("CADKernel.CacheBody", fields: 3, using: &admission)
            try encoder.field("name", body.name, using: &admission)
            try encoder.field("material", body.material, using: &admission)
            try encoder.text("topology", using: &admission)
            switch body.topology {
            case .solid(let components):
                let values = try children(components, encoder: &encoder, using: &admission, kind: Kind.component)
                let ordered = try encoder.canonicalOrder(values, using: &admission)
                try encoder.enumeration("CADKernel.CacheBodyTopology", caseName: "solid", values: 1, using: &admission)
                try encoder.field("components", ordered, using: &admission)
            case .sheet(let shellIDs):
                let values = try children(shellIDs, encoder: &encoder, using: &admission) { .shell(try shell($0)) }
                let ordered = try encoder.canonicalOrder(values, using: &admission)
                try encoder.enumeration("CADKernel.CacheBodyTopology", caseName: "sheet", values: 1, using: &admission)
                try encoder.field("shells", ordered, using: &admission)
            }
        case .component(let component):
            let voids = try children(component.voidShellIDs, encoder: &encoder, using: &admission) { .shell(try shell($0)) }
            let ordered = try encoder.canonicalOrder(voids, using: &admission)
            try encoder.record("CADKernel.CacheSolidComponent", fields: 2, using: &admission)
            try encoder.field("outer", Self(model: model, kind: .shell(try shell(component.outerShellID))), using: &admission)
            try encoder.field("voids", ordered, using: &admission)
        case .shell(let shell):
            let faces = try children(shell.faceIDs, encoder: &encoder, using: &admission) { id in
                guard let face = model.faces[id] else { throw TopologyError.missingReference("Cache content face is absent.") }
                return .face(face)
            }
            let ordered = try encoder.canonicalOrder(faces, using: &admission)
            try encoder.record("CADKernel.CacheShell", fields: 2, using: &admission)
            try encoder.field("orientation", shell.orientation, using: &admission)
            try encoder.field("faces", ordered, using: &admission)
        case .face(let face):
            guard let surface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingSurface(face.surfaceID) }
            let loops = try children(face.loops, encoder: &encoder, using: &admission) { id in
                guard let loop = model.loops[id] else { throw TopologyError.missingReference("Cache content loop is absent.") }
                return .loop(loop)
            }
            let ordered = try encoder.canonicalOrder(loops, using: &admission)
            try encoder.record("CADKernel.CacheFace", fields: 3, using: &admission)
            try encoder.field("orientation", face.orientation, using: &admission)
            try encoder.field("surface", surface, using: &admission)
            try encoder.field("loops", ordered, using: &admission)
        case .loop(let loop):
            let edges = try children(loop.coedges, encoder: &encoder, using: &admission, kind: Kind.coedge)
            try encoder.record("CADKernel.CacheLoop", fields: 2, using: &admission)
            try encoder.field("role", loop.role, using: &admission)
            try encoder.field("coedges", edges, using: &admission)
        case .coedge(let coedge):
            guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID],
                  let start = model.vertices[edge.startVertexID], let end = model.vertices[edge.endVertexID] else {
                throw TopologyError.missingReference("Cache content original edge geometry is absent.")
            }
            try encoder.record("CADKernel.CacheCoedge", fields: 6, using: &admission)
            try encoder.field("orientation", coedge.orientation, using: &admission)
            try encoder.field("start", start.point, using: &admission)
            try encoder.field("end", end.point, using: &admission)
            try encoder.field("curve", curve, using: &admission)
            try encoder.field("trim", edge.trim, using: &admission)
            try encoder.field("pcurve", coedge.surfaceParameterCurve, using: &admission)
        }
    }
}
