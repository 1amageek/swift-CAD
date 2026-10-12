import HashTreeCollections

public typealias PersistentMap<Key: Hashable, Value> = TreeDictionary<Key, Value>

public extension PersistentMap {
    func materializedDictionary() -> [Key: Value] {
        Dictionary(uniqueKeysWithValues: map { ($0.key, $0.value) })
    }
}
