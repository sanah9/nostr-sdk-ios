//
//  NostrEvent.swift
//  
//
//  Created by Bryan Montz on 5/22/23.
//

import Foundation

/// A structure that describes a Nostr event.
///
/// > Note: [NIP-01 Specification](https://github.com/nostr-protocol/nips/blob/master/01.md#events-and-signatures)
public class NostrEvent: Codable, Equatable, Hashable, AlternativeSummaryTagInterpreting, ContentWarningTagInterpreting, ExpirationTagInterpreting, LabelTagInterpreting {
    public static func == (lhs: NostrEvent, rhs: NostrEvent) -> Bool {
        lhs.id == rhs.id &&
        lhs.pubkey == rhs.pubkey &&
        lhs.createdAt == rhs.createdAt &&
        lhs.kind == rhs.kind &&
        lhs.tags == rhs.tags &&
        lhs.content == rhs.content &&
        lhs.signature == rhs.signature
    }
    
    /// 32-byte, lowercase, hex-encoded sha256 of the serialized event data.
    public let id: String
    
    /// 32-byte, lowercase, hex-encoded public key of the event creator.
    public let pubkey: String
    
    /// Unix timestamp in seconds of when the event is created.
    public let createdAt: Int64
    
    /// The event kind.
    public let kind: EventKind
    
    /// List of ``Tag`` objects.
    public let tags: [Tag]
    
    /// Arbitrary string.
    public let content: String
    
    /// 64-byte hex of the signature of the sha256 hash of the serialized event data, which is the same as the `id` field.
    public let signature: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case signature = "sig"
    }

    public init(id: String, pubkey: String, createdAt: Int64, kind: EventKind, tags: [Tag], content: String, signature: String?) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.signature = signature
    }

    /// Creates a ``NostrEvent`` rumor, which is an event with a `nil` signature.
    public required init(kind: EventKind, content: String, tags: [Tag] = [], createdAt: Int64 = Int64(Date.now.timeIntervalSince1970), pubkey: String) {
        self.kind = kind
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.pubkey = pubkey
        id = EventSerializer.identifierForEvent(withPubkey: pubkey,
                                                createdAt: createdAt,
                                                kind: kind.rawValue,
                                                tags: tags,
                                                content: content)
        signature = nil
    }

    /// Creates a signed ``NostrEvent``.
    public required init(kind: EventKind, content: String, tags: [Tag] = [], createdAt: Int64 = Int64(Date.now.timeIntervalSince1970), signedBy keypair: Keypair) throws {
        self.kind = kind
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        pubkey = keypair.publicKey.hex
        id = EventSerializer.identifierForEvent(withPubkey: keypair.publicKey.hex,
                                                createdAt: createdAt,
                                                kind: kind.rawValue,
                                                tags: tags,
                                                content: content)
        signature = try keypair.privateKey.signatureForContent(id)
    }

    /// Creates a signed ``NostrEvent`` from a rumor (unsigned) event JSON string and a private key.
    /// - Parameters:
    ///   - rumorJsonString: The JSON string representation of the rumor event, formatted according to ``NostrEvent`` coding rules.
    ///   - privkey: The private key used to sign the event.
    /// - Throws: An error if the JSON cannot be decoded or the event cannot be signed.
    public init(rumorJsonString: String, privkey: PrivateKey) throws {
        // 1. Convert the JSON string to Data
        guard let jsonData = rumorJsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unable to convert rumor JSON string to UTF-8 data."))
        }

        // 2. Decode it into a rumor event instance
        let rumor = try JSONDecoder().decode(NostrEvent.self, from: jsonData)

        // 3. Create the keypair from the private key and prepare to sign
        guard let keypair = Keypair(privateKey: privkey) else {
            throw NSError(domain: "NostrSDK.Keypair", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create keypair from private key."])
        }

        // 4. Copy fields from the rumor event, compute the id, and sign
        kind = rumor.kind
        content = rumor.content
        tags = rumor.tags
        createdAt = rumor.createdAt
        pubkey = keypair.publicKey.hex

        id = EventSerializer.identifierForEvent(withPubkey: pubkey,
                                                createdAt: createdAt,
                                                kind: kind.rawValue,
                                                tags: tags,
                                                content: content)

        signature = try keypair.privateKey.signatureForContent(id)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(pubkey)
        hasher.combine(createdAt)
        hasher.combine(kind)
        hasher.combine(tags)
        hasher.combine(content)
        hasher.combine(signature)
    }

    /// The date the event was created.
    public var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }
    
    /// The event serialized, so that it can be signed.
    public var serialized: String {
        EventSerializer.serializedEvent(withPubkey: pubkey,
                                        createdAt: createdAt,
                                        kind: kind.rawValue,
                                        tags: tags,
                                        content: content)
    }
    
    /// The event.id calculated as a SHA256 of the serialized event. See ``EventSerializer``.
    public var calculatedId: String {
        EventSerializer.identifierForEvent(withPubkey: pubkey,
                                           createdAt: createdAt,
                                           kind: kind.rawValue,
                                           tags: tags,
                                           content: content)
    }

    /// The event is a rumor if it is an unsigned event, where `signature` is `nil`.
    public var isRumor: Bool {
        signature == nil
    }

    /// Creates a copy of this event and makes it into a rumor ``NostrEvent``, where `signature` is `nil`.
    public var rumor: NostrEvent {
        NostrEvent(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, signature: nil)
    }

    /// Pubkeys referenced in this event.
    public var referencedPubkeys: [String] {
        allValues(forTagName: .pubkey)
    }

    /// Events referenced in this event.
    public var referencedEventIds: [String] {
        allValues(forTagName: .event)
    }

    /// Event coordinates referenced in this event.
    public var referencedEventCoordinates: [EventCoordinates] {
        tags.compactMap { EventCoordinates(eventCoordinatesTag: $0) }
    }

    /// All tags with the provided name.
    public func allTags(withTagName tagName: TagName) -> [Tag] {
        tags.filter { $0.name == tagName.rawValue }
    }
    
    /// The first String value for the provided ``TagName``, if it exists.
    public func firstValueForTagName(_ tag: TagName) -> String? {
        firstValueForRawTagName(tag.rawValue)
    }
    
    /// The first String value for the provided raw tag name, if it exists.
    public func firstValueForRawTagName(_ tagName: String) -> String? {
        tags.first(where: { $0.name == tagName })?.value
    }
    
    /// All values for tags with the provided name.
    /// - Parameter tag: The tag name to filter.
    /// - Returns: The values associated with the tags of the provided name.
    public func allValues(forTagName tag: TagName) -> [String] {
        tags.filter { $0.name == tag.rawValue }.map { $0.value }
    }
}

extension NostrEvent: MetadataCoding, RelayURLValidating {

    /// Gets a bare `note`-prefixed bech32-formatted human-friendly id of this event, or `nil` if it could not be generated.
    /// It is not meant to be used inside the standard NIP-01 event formats or inside the filters.
    /// They are meant for human-friendlier display and input only.
    /// Clients should still accept keys in both hex and npub format and convert internally.
    ///
    /// > Note: [NIP-19 bech32-encoded entities](https://github.com/nostr-protocol/nips/blob/master/19.md)
    public var bech32NoteId: String? {
        guard let data = id.hexDecoded else {
            return nil
        }
        return Bech32.encode(Bech32IdentifierType.note.rawValue, baseEightData: data)
    }

    /// Gets a shareable human-interactable event identifier for this event.
    /// The identifier is bech32-formatted with a prefix of `nevent` using a binary-encoded list of TLV (type-length-value).
    /// The identifier has all the information needed for the event to be found, which includes the
    /// event id, optionally the relays, optionally the author's public key, and optionally the event kind number.
    /// - Parameters:
    ///   - relayURLs: The String representations of relay URLs in which the event is more likely to be found, encoded as ASCII.
    ///   - excludeAuthor: Whether the author public key should be excluded from the identifier.
    ///   - excludeKind: Whether the event kind number should be excluded from the identifier.
    /// - Throws: `URLError.Code.badURL`, `RelayURLError.invalidScheme`, `TLVCodingError.failedToEncode`
    ///
    /// > Note: [NIP-19 bech32-encoded entities](https://github.com/nostr-protocol/nips/blob/master/19.md)
    public func nevent(relayURLStrings: [String]? = nil, excludeAuthor: Bool = false, excludeKind: Bool = false) throws -> String {
        let validatedRelayURLStrings = try relayURLStrings?.map {
            try validateRelayURLString($0)
        }.map { $0.absoluteString }

        var metadata = Metadata(relays: validatedRelayURLStrings, eventId: id)
        if !excludeAuthor {
            metadata.pubkey = pubkey
        }
        if !excludeKind {
            metadata.kind = UInt32(kind.rawValue)
        }

        return try encodedIdentifier(with: metadata, identifierType: .event)
    }

    /// Gets a shareable human-interactable event identifier for this event.
    /// The identifier is bech32-formatted with a prefix of `nevent` using a binary-encoded list of TLV (type-length-value).
    /// The identifier has all the information needed for the event to be found, which includes the
    /// event id, optionally the relays, optionally the author's public key, and optionally the event kind number.
    /// - Parameters:
    ///   - relayURLs: The String representations of relay URLs in which the event is more likely to be found, encoded as ASCII.
    ///   - excludeAuthor: Whether the author public key should be excluded from the identifier.
    ///   - excludeKind: Whether the event kind number should be excluded from the identifier.
    /// - Throws: `URLError.Code.badURL`, `RelayURLError.invalidScheme`, `TLVCodingError.failedToEncode`
    ///
    /// > Note: [NIP-19 bech32-encoded entities](https://github.com/nostr-protocol/nips/blob/master/19.md)
    public func shareableEventIdentifier(relayURLStrings: [String]? = nil, excludeAuthor: Bool = false, excludeKind: Bool = false) throws -> String {
        try nevent(relayURLStrings: relayURLStrings, excludeAuthor: excludeAuthor, excludeKind: excludeKind)
    }
}

/// This protocol describes a builder that is able to build a ``NostrEvent``.
public protocol NostrEventBuilding {
    /// The type of ``NostrEvent`` that this builder constructs.
    associatedtype EventType: NostrEvent

    /// List of ``Tag``s.
    var tags: [Tag] { get }

    /// Sets the unix timestamp in seconds of when the event is created.
    func createdAt(_ createdAt: Int64?) -> Self

    /// Appends the given list of tags to the end of the existing tags list.
    /// - Parameters:
    ///   - tags: The list of ``Tag`` objects.
    @discardableResult
    func appendTags(_ tags: Tag...) -> Self

    /// Appends the given list of tags to the end of the existing tags list.
    /// - Parameters:
    ///   - tags: The list of ``Tag`` objects.
    @discardableResult
    func appendTags(contentsOf tags: [Tag]) -> Self

    /// Inserts the given list of tags at a given index of the list.
    /// - Parameters:
    ///   - tags: The list of `Tag` objects to insert.
    ///   - index: The index of the existing list to insert the new tags into.
    ///       The tags are appended to the end of the list if the index is `nil`.
    ///       Must be a valid index of the existing tags list.
    @discardableResult
    func insertTags(_ tags: Tag..., at index: Int) -> Self

    /// Inserts the given list of tags at a given index of the list.
    /// - Parameters:
    ///   - tags: The list of `Tag` objects to insert.
    ///   - index: The index of the existing list to insert the new tags into.
    ///       The tags are appended to the end of the list if the index is `nil`.
    ///       Must be a valid index of the existing tags list.
    @discardableResult
    func insertTags(contentsOf tags: [Tag], at index: Int) -> Self

    /// Arbitrary string.
    func content(_ content: String) -> Self

    /// Builds a ``NostrEvent`` of type ``EventType`` using the properties set on the builder and signs the event.
    ///
    /// If `createdAt` is not set, the current timestamp is used.
    /// If `content` is not set, an empty string is used.
    ///
    /// - Parameter keypair: The ``Keypair`` to sign the event.
    ///
    /// Throws an error if the event could not be signed with the given keypair.
    func build(signedBy keypair: Keypair) throws -> EventType

    /// Builds a ``NostrEvent`` of type ``EventType`` using the properties set on the builder and does not sign the event,
    /// also known as a rumor event.
    ///
    /// If `createdAt` is not set, the current timestamp is used.
    /// If `content` is not set, an empty string is used.
    ///
    /// - Parameter pubkey: The ``PublicKey`` of the event creator.
    func build(pubkey: PublicKey) -> EventType

    /// Builds a ``NostrEvent`` of type ``EventType`` using the properties set on the builder and does not sign the event,
    /// also known as a rumor event.
    ///
    /// If `createdAt` is not set, the current timestamp is used.
    /// If `content` is not set, an empty string is used.
    ///
    /// - Parameter pubkey: The 32-byte, lowercase, hex-encoded public key of the event creator.
    func build(pubkey: String) -> EventType
}

public extension NostrEvent {
    /// Builder of a ``NostrEvent`` of type `T`.
    class Builder<T: NostrEvent>: NostrEventBuilding, AlternativeSummaryTagBuilding, ContentWarningTagBuilding, ExpirationTagBuilding, LabelTagBuilding {
        public typealias EventType = T

        /// The event kind.
        public final let kind: EventKind

        /// The unix timestamp in seconds of when the event is created.
        public private(set) final var createdAt: Int64?

        /// Arbitrary string.
        public private(set) final var content: String = ""

        /// List of ``Tag``s.
        public private(set) final var tags: [Tag] = []

        /// Creates a ``Builder`` from an ``EventKind``.
        public init(kind: EventKind) {
            self.kind = kind
        }

        /// Creates a ``Builder`` from a ``NostrEvent``
        /// by copying the `kind`, `tags`, and `content` properties into the builder.
        /// The `pubkey`, `createdAt`, and `signature` properties are not copied
        /// because they are computed upon building the final event.
        public init(nostrEvent: NostrEvent) {
            self.kind = nostrEvent.kind
            self.tags = nostrEvent.tags
            self.content = nostrEvent.content
        }

        @discardableResult
        public final func createdAt(_ createdAt: Int64?) -> Self {
            self.createdAt = createdAt
            return self
        }

        @discardableResult
        public final func appendTags(_ tags: Tag...) -> Self {
            appendTags(contentsOf: tags)
        }

        @discardableResult
        public final func appendTags(contentsOf tags: [Tag]) -> Self {
            self.tags.append(contentsOf: tags)
            return self
        }

        @discardableResult
        public final func insertTags(_ tags: Tag..., at index: Int) -> Self {
            insertTags(contentsOf: tags, at: index)
        }

        @discardableResult
        public final func insertTags(contentsOf tags: [Tag], at index: Int) -> Self {
            self.tags.insert(contentsOf: tags, at: index)
            return self
        }

        @discardableResult
        public final func content(_ content: String) -> Self {
            self.content = content
            return self
        }

        public func build(signedBy keypair: Keypair) throws -> T {
            try T(
                kind: kind,
                content: content,
                tags: tags,
                createdAt: createdAt ?? Int64(Date.now.timeIntervalSince1970),
                signedBy: keypair
            )
        }

        public final func build(pubkey: PublicKey) -> T {
            build(pubkey: pubkey.hex)
        }

        public final func build(pubkey: String) -> T {
            T(
                kind: kind,
                content: content,
                tags: tags,
                createdAt: createdAt ?? Int64(Date.now.timeIntervalSince1970),
                pubkey: pubkey
            )
        }
    }
}
