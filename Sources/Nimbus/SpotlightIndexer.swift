import CoreSpotlight
import Foundation

/// Publishes `ToolCatalog` to the system Spotlight index so tools show up in
/// Spotlight search. A selection comes back as a `CSSearchableItemActionType`
/// user activity, handled by `AppDelegate`.
enum SpotlightIndexer {
    static let domainIdentifier = "com.treendz.nimbus.tools"

    /// Idempotent: clears the domain and indexes the current catalog, so a
    /// tool removed from the catalog leaves the index too.
    static func reindex() {
        let index = CSSearchableIndex.default()
        let items = ToolCatalog.tools.map { tool -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = tool.name
            attributes.contentDescription = tool.summary
            attributes.keywords = ["Nimbus", tool.group.title, tool.name]
            return CSSearchableItem(
                uniqueIdentifier: tool.id,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
        index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
            index.indexSearchableItems(items)
        }
    }
}
