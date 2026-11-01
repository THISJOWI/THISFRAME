import Foundation

/// Full user record from `GET /Users/{id}`.
///
/// `JellyfinUser` is the tiny identity carried by the auth response; this is
/// the richer profile the Profile screen needs (administrator flag, avatar
/// tag, activity dates).
public struct JellyfinUserProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let primaryImageTag: String?
    public let isAdministrator: Bool
    public let lastLoginDate: String?
    public let lastActivityDate: String?
    public let hasPassword: Bool?

    public init(
        id: String,
        name: String,
        primaryImageTag: String? = nil,
        isAdministrator: Bool = false,
        lastLoginDate: String? = nil,
        lastActivityDate: String? = nil,
        hasPassword: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.primaryImageTag = primaryImageTag
        self.isAdministrator = isAdministrator
        self.lastLoginDate = lastLoginDate
        self.lastActivityDate = lastActivityDate
        self.hasPassword = hasPassword
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case primaryImageTag = "PrimaryImageTag"
        case policy = "Policy"
        case lastLoginDate = "LastLoginDate"
        case lastActivityDate = "LastActivityDate"
        case hasPassword = "HasPassword"
    }

    private struct Policy: Codable {
        let isAdministrator: Bool?

        enum CodingKeys: String, CodingKey {
            case isAdministrator = "IsAdministrator"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        primaryImageTag = try container.decodeIfPresent(String.self, forKey: .primaryImageTag)
        lastLoginDate = try container.decodeIfPresent(String.self, forKey: .lastLoginDate)
        lastActivityDate = try container.decodeIfPresent(String.self, forKey: .lastActivityDate)
        hasPassword = try container.decodeIfPresent(Bool.self, forKey: .hasPassword)
        isAdministrator = (try container.decodeIfPresent(Policy.self, forKey: .policy))?
            .isAdministrator ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(primaryImageTag, forKey: .primaryImageTag)
        try container.encodeIfPresent(lastLoginDate, forKey: .lastLoginDate)
        try container.encodeIfPresent(lastActivityDate, forKey: .lastActivityDate)
        try container.encodeIfPresent(hasPassword, forKey: .hasPassword)
        try container.encode(Policy(isAdministrator: isAdministrator), forKey: .policy)
    }
}
