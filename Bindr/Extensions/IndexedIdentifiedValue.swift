import Foundation

struct IndexedIdentifiedValue<Value: Identifiable>: Identifiable {
    let index: Int
    let value: Value

    var id: Value.ID { value.id }
}

extension Array where Element: Identifiable {
    var indexedIdentifiedValues: [IndexedIdentifiedValue<Element>] {
        enumerated().map { IndexedIdentifiedValue(index: $0.offset, value: $0.element) }
    }
}
