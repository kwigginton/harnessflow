import Foundation
import Testing
@testable import HarnessflowCore

struct LinearIssueImportTests {
    @Test
    func graphQLRequestUsesAuthorizationHeaderAndIssueIdentifier() throws {
        let client = LinearGraphQLClient(endpoint: URL(string: "https://linear.example/graphql")!)

        let request = try client.makeRequest(
            query: "query HarnessflowLinearIssueImport($id: String!) { issue(id: $id) { id } }",
            variables: ["id": "ENG-123"],
            apiToken: "lin_api_test"
        )

        #expect(request.url?.absoluteString == "https://linear.example/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["query"] as? String)?.contains("issue(id: $id)") == true)
        #expect((json["variables"] as? [String: String])?["id"] == "ENG-123")
    }

    @Test
    func importIssueMapsLinearResponseAndSortsCommentsInFormatter() async throws {
        let transport = StubLinearTransport(
            data: """
            {
              "data": {
                "issue": {
                  "id": "issue-id",
                  "identifier": "ENG-123",
                  "title": "Import from Linear",
                  "url": "https://linear.app/acme/issue/ENG-123/import-from-linear",
                  "description": "Issue description",
                  "comments": {
                    "nodes": [
                      {
                        "id": "newer",
                        "body": "Second comment",
                        "createdAt": "2026-05-16T12:00:00Z",
                        "user": { "name": "Taylor", "displayName": null, "email": null }
                      },
                      {
                        "id": "older",
                        "body": "First comment",
                        "createdAt": "2026-05-16T11:00:00Z",
                        "user": { "name": "Morgan", "displayName": "Morgan Lee", "email": "morgan@example.com" }
                      }
                    ]
                  },
                  "attachments": {
                    "nodes": [
                      {
                        "id": "file",
                        "title": "screenshot.png",
                        "subtitle": "image/png",
                        "url": "https://uploads.linear.app/file.png"
                      }
                    ]
                  }
                }
              }
            }
            """.data(using: .utf8)!
        )
        let client = LinearGraphQLClient(
            endpoint: URL(string: "https://linear.example/graphql")!,
            transport: transport
        )

        let issue = try await client.importIssue(identifier: "ENG-123", apiToken: "lin_api_test")
        let markdown = LinearIssueImportFormatter().markdown(for: issue)

        #expect(issue.harnessflowTitle == "ENG-123: Import from Linear")
        #expect(markdown.contains("Source: ENG-123"))
        #expect(markdown.contains("## Description\n\nIssue description"))
        let firstCommentIndex = try #require(markdown.range(of: "First comment")?.lowerBound)
        let secondCommentIndex = try #require(markdown.range(of: "Second comment")?.lowerBound)
        #expect(firstCommentIndex < secondCommentIndex)
        #expect(markdown.contains("- [screenshot.png](https://uploads.linear.app/file.png) - image/png"))
    }

    @Test
    func viewerValidationMapsViewerResponse() async throws {
        let transport = StubLinearTransport(
            data: """
            {
              "data": {
                "viewer": {
                  "id": "viewer-id",
                  "name": "Ken",
                  "email": "ken@example.com"
                }
              }
            }
            """.data(using: .utf8)!
        )
        let client = LinearGraphQLClient(
            endpoint: URL(string: "https://linear.example/graphql")!,
            transport: transport
        )

        let viewer = try await client.validateToken("lin_api_test")

        #expect(viewer == LinearViewer(id: "viewer-id", name: "Ken", email: "ken@example.com"))
    }

    @Test
    func executionPromptIncludesFormattedLinearDetails() throws {
        let issue = LinearIssueImport(
            id: "issue-id",
            identifier: "ENG-123",
            title: "Import from Linear",
            url: "https://linear.app/acme/issue/ENG-123/import-from-linear",
            description: "Linear issue body",
            comments: [
                LinearIssueComment(id: "comment", body: "Linear comment", createdAt: "2026-05-16T12:00:00Z", authorName: "Morgan")
            ],
            attachments: [
                LinearIssueAttachment(id: "file", title: "mockup.png", url: "https://uploads.linear.app/mockup.png")
            ]
        )
        let ticket = Ticket(
            title: issue.harnessflowTitle,
            detailsText: LinearIssueImportFormatter().markdown(for: issue),
            column: .research
        )
        let settings = AppSettings(
            defaultWorkingDirectory: "/tmp/workdir",
            phasePrompts: PhasePromptSelection(research: "Research base prompt")
        )

        let request = try TicketRunRequestBuilder().makeRequest(for: ticket, settings: settings)

        #expect(request.prompt.contains("Title: ENG-123: Import from Linear"))
        #expect(request.prompt.contains("Source: ENG-123"))
        #expect(request.prompt.contains("Linear issue body"))
        #expect(request.prompt.contains("Linear comment"))
        #expect(request.prompt.contains("https://uploads.linear.app/mockup.png"))
    }
}

private struct StubLinearTransport: LinearHTTPTransport {
    var data: Data
    var statusCode: Int = 200

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
