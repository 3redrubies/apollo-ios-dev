import GraphQLCompiler

public actor FieldCollector {

  typealias CollectedField = (String, GraphQLType, deprecationReason: String?)

  private typealias FieldInfo = (GraphQLType, deprecationReason: String?)

  /// A response key in `collectedFields(for:)` that was chosen from different schema fields
  /// whose types or deprecation reasons differ.
  public struct ResponseKeyConflict: Sendable {
    public let responseKey: String
    /// The schema fields selected with the response key. The first is the one used in
    /// `collectedFields(for:)`.
    public let fields: [(name: String, type: GraphQLType, deprecationReason: String?)]
  }

  /// Collected fields keyed by response key, then by the name of the schema field that was
  /// selected with that response key.
  private var collectedFields: [GraphQLCompositeType: [String: [String: FieldInfo]]] = [:]

  func collectFields(from selectionSet: CompilationResult.SelectionSet) {
    guard let type = selectionSet.parentType as? (any GraphQLInterfaceImplementingType) else { return }
    for case let .field(field) in selectionSet.selections {
      add(field: field, to: type)
    }
  }

  func add<T: Sequence>(
    fields: T,
    to type: any GraphQLInterfaceImplementingType
  ) where T.Element == CompilationResult.Field {
    for field in fields {
      add(field: field, to: type)
    }
  }

  func add(
    field: CompilationResult.Field,
    to type: any GraphQLInterfaceImplementingType
  ) {
    collectedFields[type, default: [:]][field.responseKey, default: [:]][field.name] =
      (field.type, deprecationReason: field.deprecationReason)
  }

  public func collectedFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [(String, GraphQLType, deprecationReason: String?)] {
    candidateFields(for: type)
      .sorted { $0.key < $1.key }
      .compactMap { key, candidates in
        Self.sorted(candidates).first.map { (key, $0.value.0, $0.value.deprecationReason) }
      }
  }

  /// The response keys in `collectedFields(for:)` that were chosen from different schema fields
  /// whose types or deprecation reasons differ, sorted by response key.
  public func responseKeyConflicts(
    for type: any GraphQLInterfaceImplementingType
  ) -> [ResponseKeyConflict] {
    candidateFields(for: type)
      .sorted { $0.key < $1.key }
      .compactMap { responseKey, candidates in
        let sortedCandidates = Self.sorted(candidates)
        guard let first = sortedCandidates.first?.value,
              sortedCandidates.contains(where: { $0.value != first }) else {
          return nil
        }

        return ResponseKeyConflict(
          responseKey: responseKey,
          fields: sortedCandidates.map { ($0.key, $0.value.0, $0.value.deprecationReason) }
        )
      }
  }

  /// The schema fields selected with each response key, from `type` itself or else from the
  /// first of its interfaces that selects the response key.
  private func candidateFields(
    for type: any GraphQLInterfaceImplementingType
  ) -> [String: [String: FieldInfo]] {
    var fields = collectedFields[type] ?? [:]

    for interface in type.interfaces {
      if let interfaceFields = collectedFields[interface] {
        fields.merge(interfaceFields) { field, _ in field }
      }
    }

    return fields
  }

  private static func sorted(_ candidates: [String: FieldInfo]) -> [(key: String, value: FieldInfo)] {
    candidates.sorted {
      if isOrdered($0.value, before: $1.value) { return true }
      if isOrdered($1.value, before: $0.value) { return false }
      return $0.key < $1.key
    }
  }

  private static func isOrdered(_ lhs: FieldInfo, before rhs: FieldInfo) -> Bool {
    guard lhs.0 == rhs.0 else { return isOrdered(lhs.0, before: rhs.0) }

    switch (lhs.deprecationReason, rhs.deprecationReason) {
    case let (lhsReason?, rhsReason?):
      return lhsReason.utf8.lexicographicallyPrecedes(rhsReason.utf8)

    case (nil, .some):
      return true

    default:
      return false
    }
  }

  /// Orders nullable types before non-null types, outermost wrapper first, then named types
  /// before lists, then named types by schema name.
  private static func isOrdered(_ lhs: GraphQLType, before rhs: GraphQLType) -> Bool {
    switch (lhs, rhs) {
    case let (.nonNull(lhsType), .nonNull(rhsType)),
         let (.list(lhsType), .list(rhsType)):
      return isOrdered(lhsType, before: rhsType)

    case (_, .nonNull):
      return true

    case (.nonNull, _):
      return false

    case (_, .list):
      return true

    case (.list, _):
      return false

    default:
      return lhs.namedType.name.schemaName < rhs.namedType.name.schemaName
    }
  }
}
