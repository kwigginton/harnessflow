import Foundation

public struct AgentQuestionSet: Codable, Equatable, Sendable {
    public var id: UUID
    public var questions: [AgentQuestion]

    public init(id: UUID = UUID(), questions: [AgentQuestion]) {
        self.id = id
        self.questions = questions
    }
}

public struct AgentQuestion: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var prompt: String
    public var choices: [AgentQuestionChoice]
    public var allowsFreeform: Bool
    public var defaultChoiceID: String?

    public init(
        id: String,
        prompt: String,
        choices: [AgentQuestionChoice] = [],
        allowsFreeform: Bool = false,
        defaultChoiceID: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.choices = choices
        self.allowsFreeform = allowsFreeform
        self.defaultChoiceID = defaultChoiceID
    }
}

public struct AgentQuestionChoice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

public struct AgentAnswer: Codable, Equatable, Sendable {
    public var questionID: String
    public var choiceID: String?
    public var freeformText: String?

    public init(questionID: String, choiceID: String? = nil, freeformText: String? = nil) {
        self.questionID = questionID
        self.choiceID = choiceID
        self.freeformText = freeformText
    }
}

public enum AgentQuestionContract {
    public static let startMarker = "<<<HARNESSFLOW_QUESTIONS_START>>>"
    public static let endMarker = "<<<HARNESSFLOW_QUESTIONS_END>>>"

    public static var instructions: String {
        """
        Agent Q&A Contract
        If you are blocked on a user decision, do not guess and do not return a final deliverable. Return only a JSON question set wrapped exactly between these markers:

        \(startMarker)
        {"id":"00000000-0000-0000-0000-000000000000","questions":[{"id":"decision","prompt":"Which option should I use?","choices":[{"id":"a","label":"Option A","description":"Use A."}],"allowsFreeform":false,"defaultChoiceID":"a"}]}
        \(endMarker)

        Use stable question ids. Use choices for single-selection decisions. Set allowsFreeform to true for text answers.
        """
    }

    public static func extractQuestionSet(from output: String) -> AgentQuestionSet? {
        guard let startRange = output.range(of: startMarker) else {
            return nil
        }

        let contentStart = startRange.upperBound
        guard let endRange = output.range(of: endMarker, range: contentStart..<output.endIndex) else {
            return nil
        }

        let json = output[contentStart..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard json.isEmpty == false, let data = json.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(AgentQuestionSet.self, from: data)
    }
}
