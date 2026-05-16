import Foundation

public protocol LinearIssueImporting: Sendable {
    func importIssue(identifier: String, apiToken: String) async throws -> LinearIssueImport
    func validateToken(_ apiToken: String) async throws -> LinearViewer
}

public protocol LinearHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private struct URLSessionLinearHTTPTransport: LinearHTTPTransport, @unchecked Sendable {
    let session: URLSession

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public struct LinearViewer: Equatable, Sendable {
    public var id: String
    public var name: String
    public var email: String?

    public init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }
}

public struct LinearIssueImport: Equatable, Sendable {
    public var id: String
    public var identifier: String
    public var title: String
    public var url: String?
    public var description: String
    public var comments: [LinearIssueComment]
    public var attachments: [LinearIssueAttachment]

    public init(
        id: String,
        identifier: String,
        title: String,
        url: String? = nil,
        description: String = "",
        comments: [LinearIssueComment] = [],
        attachments: [LinearIssueAttachment] = []
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.url = url
        self.description = description
        self.comments = comments
        self.attachments = attachments
    }

    public var harnessflowTitle: String {
        "\(identifier): \(title)"
    }
}

public struct LinearIssueComment: Equatable, Sendable {
    public var id: String
    public var body: String
    public var createdAt: String
    public var authorName: String

    public init(id: String, body: String, createdAt: String, authorName: String) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.authorName = authorName
    }
}

public struct LinearIssueAttachment: Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var subtitle: String?

    public init(id: String, title: String, url: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.subtitle = subtitle
    }
}

public enum LinearImportError: LocalizedError, Equatable, Sendable {
    case missingIdentifier
    case missingAPIToken
    case invalidResponse
    case httpFailure(Int)
    case issueNotFound(String)
    case graphQLError(String)

    public var errorDescription: String? {
        switch self {
        case .missingIdentifier:
            "Enter a Linear issue identifier."
        case .missingAPIToken:
            "Add a Linear API key in Settings before importing an issue."
        case .invalidResponse:
            "Linear returned a response Harnessflow could not read."
        case let .httpFailure(statusCode):
            "Linear request failed with HTTP \(statusCode)."
        case let .issueNotFound(identifier):
            "Linear issue not found: \(identifier)."
        case let .graphQLError(message):
            "Linear returned an error: \(message)"
        }
    }
}

public struct LinearIssueImportFormatter: Sendable {
    public init() {}

    public func markdown(for issue: LinearIssueImport) -> String {
        var sections: [String] = []
        var sourceLines = [
            "# Linear Issue",
            "",
            "Source: \(issue.identifier)",
        ]
        if let url = trimmedOptional(issue.url) {
            sourceLines.append("URL: \(url)")
        }
        sections.append(sourceLines.joined(separator: "\n"))

        let description = issue.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty == false {
            sections.append(
                """
                ## Description

                \(description)
                """
            )
        }

        let comments = issue.comments
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { comment -> String? in
                let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard body.isEmpty == false else {
                    return nil
                }
                return """
                ### \(comment.authorName) - \(comment.createdAt)

                \(body)
                """
            }
        if comments.isEmpty == false {
            sections.append(
                """
                ## Comments

                \(comments.joined(separator: "\n\n"))
                """
            )
        }

        let attachments = issue.attachments
            .filter { $0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .map { attachment in
                let title = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? attachment.url
                    : attachment.title
                if let subtitle = trimmedOptional(attachment.subtitle) {
                    return "- [\(title)](\(attachment.url)) - \(subtitle)"
                }
                return "- [\(title)](\(attachment.url))"
            }
        if attachments.isEmpty == false {
            sections.append(
                """
                ## Files and Images

                \(attachments.joined(separator: "\n"))
                """
            )
        }

        return sections.joined(separator: "\n\n")
    }

    private func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct LinearGraphQLClient: LinearIssueImporting {
    public static let defaultEndpoint = URL(string: "https://api.linear.app/graphql")!

    private let endpoint: URL
    private let transport: any LinearHTTPTransport

    public init(endpoint: URL = LinearGraphQLClient.defaultEndpoint) {
        self.endpoint = endpoint
        self.transport = URLSessionLinearHTTPTransport(session: .shared)
    }

    public init(endpoint: URL = LinearGraphQLClient.defaultEndpoint, transport: any LinearHTTPTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }

    public func importIssue(identifier: String, apiToken: String) async throws -> LinearIssueImport {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedIdentifier.isEmpty == false else {
            throw LinearImportError.missingIdentifier
        }

        let response: GraphQLResponse<IssueImportData> = try await perform(
            query: Self.issueImportQuery,
            variables: ["id": trimmedIdentifier],
            apiToken: apiToken
        )
        guard let issue = response.data?.issue else {
            throw LinearImportError.issueNotFound(trimmedIdentifier)
        }

        return LinearIssueImport(
            id: issue.id,
            identifier: issue.identifier,
            title: issue.title,
            url: issue.url,
            description: issue.description ?? "",
            comments: issue.comments.nodes.map { comment in
                LinearIssueComment(
                    id: comment.id,
                    body: comment.body,
                    createdAt: comment.createdAt,
                    authorName: comment.user?.displayName
                        ?? comment.user?.name
                        ?? comment.user?.email
                        ?? "Unknown"
                )
            },
            attachments: issue.attachments.nodes.compactMap { attachment in
                guard let url = attachment.url, url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    return nil
                }
                return LinearIssueAttachment(
                    id: attachment.id,
                    title: attachment.title ?? attachment.subtitle ?? url,
                    url: url,
                    subtitle: attachment.subtitle
                )
            }
        )
    }

    public func validateToken(_ apiToken: String) async throws -> LinearViewer {
        let response: GraphQLResponse<ViewerData> = try await perform(
            query: Self.viewerQuery,
            variables: [:],
            apiToken: apiToken
        )
        guard let viewer = response.data?.viewer else {
            throw LinearImportError.invalidResponse
        }
        return LinearViewer(id: viewer.id, name: viewer.name, email: viewer.email)
    }

    public func makeRequest(query: String, variables: [String: String], apiToken: String) throws -> URLRequest {
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedToken.isEmpty == false else {
            throw LinearImportError.missingAPIToken
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedToken, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        return request
    }

    private func perform<Response: Decodable>(
        query: String,
        variables: [String: String],
        apiToken: String
    ) async throws -> GraphQLResponse<Response> {
        let request = try makeRequest(query: query, variables: variables, apiToken: apiToken)
        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinearImportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LinearImportError.httpFailure(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GraphQLResponse<Response>.self, from: data)
        if let message = decoded.errors?.map(\.message).joined(separator: "\n"), message.isEmpty == false {
            throw LinearImportError.graphQLError(message)
        }
        return decoded
    }

    private static let viewerQuery = """
    query HarnessflowLinearViewer {
      viewer {
        id
        name
        email
      }
    }
    """

    private static let issueImportQuery = """
    query HarnessflowLinearIssueImport($id: String!) {
      issue(id: $id) {
        id
        identifier
        title
        url
        description
        comments(first: 100) {
          nodes {
            id
            body
            createdAt
            user {
              name
              displayName
              email
            }
          }
        }
        attachments(first: 100) {
          nodes {
            id
            title
            subtitle
            url
          }
        }
      }
    }
    """
}

private struct GraphQLRequest: Encodable {
    var query: String
    var variables: [String: String]
}

private struct GraphQLResponse<DataPayload: Decodable>: Decodable {
    var data: DataPayload?
    var errors: [GraphQLError]?
}

private struct GraphQLError: Decodable {
    var message: String
}

private struct ViewerData: Decodable {
    var viewer: Viewer

    struct Viewer: Decodable {
        var id: String
        var name: String
        var email: String?
    }
}

private struct IssueImportData: Decodable {
    var issue: Issue?

    struct Issue: Decodable {
        var id: String
        var identifier: String
        var title: String
        var url: String?
        var description: String?
        var comments: Connection<Comment>
        var attachments: Connection<Attachment>
    }

    struct Comment: Decodable {
        var id: String
        var body: String
        var createdAt: String
        var user: User?
    }

    struct User: Decodable {
        var name: String?
        var displayName: String?
        var email: String?
    }

    struct Attachment: Decodable {
        var id: String
        var title: String?
        var subtitle: String?
        var url: String?
    }
}

private struct Connection<Node: Decodable>: Decodable {
    var nodes: [Node]
}
