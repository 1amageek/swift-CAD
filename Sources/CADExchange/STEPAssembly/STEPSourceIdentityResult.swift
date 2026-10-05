import CADCore

struct STEPSourceIdentityResult {
    let values: [Int: PortableIdentity128]
    let documentCarriers: [Int: PortableIdentity128]
    let consumedWork: Int
    let textBytes: Int
}
