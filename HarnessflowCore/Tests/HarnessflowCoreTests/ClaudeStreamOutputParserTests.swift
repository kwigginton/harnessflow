import Testing
@testable import HarnessflowCore

struct ClaudeStreamOutputParserTests {
    @Test
    func streamResultExtractsFinalOutputAndReadableStatus() {
        var parser = ClaudeStreamOutputParser()
        let resultLine = #"{"type":"result","subtype":"success","is_error":false,"result":"\#(PhaseDeliverableContract.startMarker)\n## Done\n\#(PhaseDeliverableContract.endMarker)"}"#

        let chunks = parser.append(
            """
            {"type":"system","subtype":"init","session_id":"abcdef123456","model":"sonnet"}
            {"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":"Drafting final deliverable..."}]}}
            \(resultLine)

            """
        )

        let liveOutput = chunks.joined()
        #expect(liveOutput.contains("[Claude] Session started"))
        #expect(liveOutput.contains("sonnet"))
        #expect(liveOutput.contains("Drafting final deliverable..."))
        #expect(parser.output == """
        \(PhaseDeliverableContract.startMarker)
        ## Done
        \(PhaseDeliverableContract.endMarker)
        """)
    }

    @Test
    func streamTextDeltasFallbackToAccumulatedAssistantText() {
        var parser = ClaudeStreamOutputParser()

        let firstChunks = parser.append(
            #"{"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":"Plan"}]}}"# + "\n"
        )
        let secondChunks = parser.append(
            #"{"type":"assistant","message":{"id":"msg_1","content":[{"type":"text","text":"Plan complete"}]}}"# + "\n"
        )

        #expect(firstChunks.joined() == "Plan")
        #expect(secondChunks.joined() == " complete")
        #expect(parser.output == "Plan complete")
    }

    @Test
    func streamToolUseEmitsReadableToolStatus() {
        var parser = ClaudeStreamOutputParser()

        let chunks = parser.append(
            """
            {"type":"assistant","message":{"id":"msg_2","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"swift test --package-path HarnessflowCore"}}]}}

            """
        )

        #expect(chunks.joined().contains("[Claude] Using Bash: swift test --package-path HarnessflowCore"))
        #expect(parser.output.isEmpty)
    }

    @Test
    func streamRetryEventsEmitReadableRetryStatus() {
        var parser = ClaudeStreamOutputParser()

        let chunks = parser.append(
            """
            {"type":"system","subtype":"api_retry","message":"Rate limit hit; retrying in 2 seconds."}

            """
        )

        #expect(chunks.joined().contains("[Claude] API retry: Rate limit hit; retrying in 2 seconds."))
        #expect(parser.output.isEmpty)
    }
}
