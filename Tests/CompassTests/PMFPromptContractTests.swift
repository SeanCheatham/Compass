import Foundation
import Testing

@testable import Compass

struct PMFPromptContractTests {
  @Test func personaActionPromptIncludesStrictGuardrailsAndAllowedActions() throws {
    let context = makeActionPromptContext()

    let prompt = try Prompts.pmfPersonaActionPrompt(context: context)

    try #require(prompt.contains(Prompts.pmfPersonaActionPromptVersionID))
    try #require(prompt.contains("invent hidden features"))
    try #require(prompt.contains("Unknown top-level fields are rejected"))
    try #require(prompt.contains("inspect_value_prop"))
    try #require(prompt.contains("\"additionalProperties\": false"))
    try #require(prompt.contains("\"allowedActions\""))
  }

  @Test func personaActionResponseDecodesToVersionedChoice() throws {
    let allowedActions = makeAllowedActions()
    let json = """
      {
        "actionId": "inspect_value_prop",
        "params": { "depth": "quick" },
        "rationale": "I need to test whether the claim connects to my reporting pain.",
        "expectation": "I expect a concrete workflow, not another tagline.",
        "confusion": null
      }
      """

    let output = try Prompts.decodePMFPersonaActionResponse(json, allowedActions: allowedActions)

    try #require(output.promptVersionID == Prompts.pmfPersonaActionPromptVersionID)
    try #require(output.action.id == "inspect_value_prop")
    try #require(output.rationale.contains("reporting pain"))
    try #require(output.choice.promptVersionID == Prompts.pmfPersonaActionPromptVersionID)
    guard case .object(let params) = output.action.params else {
      Issue.record("params should decode as object")
      return
    }
    try #require(params["depth"] == .string("quick"))
  }

  @Test func personaActionResponseRejectsInvalidActionAndUnknownFields() throws {
    let allowedActions = makeAllowedActions()
    #expect(throws: PMFPromptValidationError.actionNotAllowed(
      actionID: "invent_new_button",
      allowedActionIDs: allowedActions.map(\.id)
    )) {
      try Prompts.decodePMFPersonaActionResponse(
        """
        {
          "actionId": "invent_new_button",
          "params": {},
          "rationale": "I want a button that is not visible.",
          "expectation": "I expect a made-up feature.",
          "confusion": null
        }
        """,
        allowedActions: allowedActions
      )
    }

    #expect(throws: PMFPromptValidationError.unknownFields(["extra"])) {
      try Prompts.decodePMFPersonaActionResponse(
        """
        {
          "actionId": "inspect_value_prop",
          "params": {},
          "rationale": "This is allowed.",
          "expectation": "I expect proof.",
          "confusion": null,
          "extra": "nope"
        }
        """,
        allowedActions: allowedActions
      )
    }
  }

  @Test func personaActionResponseRejectsNonObjectParamsAndEmptyRationale() throws {
    let allowedActions = makeAllowedActions()
    #expect(throws: PMFPromptValidationError.paramsMustBeObject) {
      try Prompts.decodePMFPersonaActionResponse(
        """
        {
          "actionId": "inspect_value_prop",
          "params": [],
          "rationale": "This is allowed.",
          "expectation": "I expect proof.",
          "confusion": null
        }
        """,
        allowedActions: allowedActions
      )
    }

    #expect(throws: PMFPromptValidationError.emptyField("rationale")) {
      try Prompts.decodePMFPersonaActionResponse(
        """
        {
          "actionId": "inspect_value_prop",
          "params": {},
          "rationale": "   ",
          "expectation": "I expect proof.",
          "confusion": null
        }
        """,
        allowedActions: allowedActions
      )
    }
  }

  @Test func feedbackPromptIncludesScoresEnumsAndSkepticismRules() throws {
    let context = makeFeedbackPromptContext()

    let prompt = try Prompts.pmfFeedbackPrompt(context: context)

    try #require(prompt.contains(Prompts.pmfFeedbackPromptVersionID))
    try #require(prompt.contains("1 = very weak"))
    try #require(prompt.contains("strong_pull"))
    try #require(prompt.contains("wrong_user"))
    try #require(prompt.contains("hidden capabilities"))
    try #require(prompt.contains("\"additionalProperties\": false"))
    try #require(prompt.contains("\"terminalStatus\""))
  }

  @Test func feedbackResponseDecodesWithPromptVersion() throws {
    let output = try Prompts.decodePMFFeedbackResponse(validFeedbackJSON())

    try #require(output.promptVersionID == Prompts.pmfFeedbackPromptVersionID)
    try #require(output.valueScore == 3)
    try #require(output.clarityScore == 2)
    try #require(output.taskOutcome == .partial)
    try #require(output.verdict == .notYet)
    try #require(output.topObjection.contains("spreadsheet"))
  }

  @Test func feedbackResponseRejectsInvalidScoreEnumAndUnknownField() throws {
    #expect(throws: PMFPromptValidationError.scoreOutOfRange(field: "valueScore", value: 6)) {
      try Prompts.decodePMFFeedbackResponse(
        validFeedbackJSON(replacements: ["\"valueScore\": 3": "\"valueScore\": 6"])
      )
    }

    #expect(throws: PMFPromptValidationError.invalidEnum(
      field: "verdict",
      value: "maybe",
      allowedValues: PMFPersonaVerdict.allCases.map(\.rawValue)
    )) {
      try Prompts.decodePMFFeedbackResponse(
        validFeedbackJSON(replacements: ["\"verdict\": \"not_yet\"": "\"verdict\": \"maybe\""])
      )
    }

    #expect(throws: PMFPromptValidationError.unknownFields(["extra"])) {
      try Prompts.decodePMFFeedbackResponse(
        """
        {
          "valueScore": 3,
          "clarityScore": 2,
          "trustScore": 3,
          "switchLikelihood": 2,
          "payLikelihood": 1,
          "taskOutcome": "partial",
          "topObjection": "I still cannot tell how this replaces my current spreadsheet.",
          "missingCapability": "A concrete import or reporting example.",
          "momentOfDelight": null,
          "momentOfConfusion": "The first screen says ready but not ready for what.",
          "verdict": "not_yet",
          "summary": "The promise is plausible, but the experience does not prove value quickly.",
          "extra": "nope"
        }
        """
      )
    }
  }

  @Test func repairPromptsNameValidationErrorsAndPreserveContext() throws {
    let actionContext = makeActionPromptContext()
    let actionRepair = try Prompts.pmfPersonaActionRepairPrompt(
      validationError: .actionNotAllowed(
        actionID: "invent_new_button",
        allowedActionIDs: actionContext.allowedActions.map(\.id)
      ),
      context: actionContext
    )

    try #require(actionRepair.contains("invent_new_button"))
    try #require(actionRepair.contains("inspect_value_prop"))
    try #require(actionRepair.contains("Return only valid JSON"))
    try #require(actionRepair.contains(Prompts.pmfPersonaActionPromptVersionID))

    let feedbackRepair = try Prompts.pmfFeedbackRepairPrompt(
      validationError: .scoreOutOfRange(field: "valueScore", value: 6),
      context: makeFeedbackPromptContext()
    )

    try #require(feedbackRepair.contains("valueScore"))
    try #require(feedbackRepair.contains("1 through 5"))
    try #require(feedbackRepair.contains(Prompts.pmfFeedbackPromptVersionID))
    try #require(feedbackRepair.contains("\"terminalStatus\""))
  }
}

private func makeActionPromptContext() -> PMFPersonaActionPromptContext {
  PMFPersonaActionPromptContext(
    request: makePMFPromptRequestContext(),
    turnIndex: 1,
    maxTurns: 6,
    trace: makePromptTrace(),
    allowedActions: makeAllowedActions(),
    priorTranscript: [
      PMFPersonaActionTranscriptEntry(
        turnIndex: 0,
        phase: .choose,
        chosenActionID: "start_core_workflow",
        wasValid: true,
        allowedActionIDs: ["start_core_workflow"],
        rationale: "I want to see whether the workflow exists.",
        rawResponse: #"{"actionId":"start_core_workflow"}"#
      )
    ]
  )
}

private func makeFeedbackPromptContext() -> PMFFeedbackPromptContext {
  PMFFeedbackPromptContext(
    request: makePMFPromptRequestContext(),
    trace: makePromptTrace(terminal: true),
    actionTranscript: makeActionPromptContext().priorTranscript
  )
}

private func makePMFPromptRequestContext() -> PMFSimulationRequestContext {
  let config = PMFConfig.seedDefaults(
    projectTitle: "Compass PMF",
    vision: "A tool for proving product fit with generated apps.",
    now: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let hypothesis = config.hypotheses[0]
  let persona = config.personas[0]
  let task = config.tasks[0]
  let scenario = PMFScenario(
    id: "scenario",
    title: "Scenario",
    hypothesisID: hypothesis.id,
    personaID: persona.id,
    taskID: task.id,
    seed: "scenario-seed"
  )
  return PMFSimulationRequestContext(
    projectTitle: "Compass PMF",
    hypothesis: hypothesis,
    persona: persona,
    task: task,
    scenario: scenario,
    settings: AgentRuntimeSettings()
  )
}

private func makePromptTrace(terminal: Bool = false) -> PMFExperienceTrace {
  let initialState = PMFExperienceState(
    id: "initial",
    headline: "Ready to evaluate the product promise",
    body: "A skeptical operator is trying to reduce weekly reporting work.",
    semanticNodes: [
      PMFExperienceNode(
        id: "screen.headline",
        role: "heading",
        text: "Ready to evaluate the product promise"
      ),
      PMFExperienceNode(
        id: "screen.body",
        role: "text",
        text: "Try the workflow before deciding whether to switch."
      ),
    ],
    observations: ["value proposition visible", "core workflow entry point visible"],
    terminal: false
  )
  let terminalState = PMFExperienceState(
    id: "workflow_completed",
    headline: "Workflow outcome shown",
    body: "The app returns a deterministic outcome for the reporting workflow.",
    semanticNodes: [
      PMFExperienceNode(id: "screen.outcome", role: "text", text: "Outcome ready")
    ],
    observations: ["workflow completed", "outcome ready for feedback"],
    terminal: terminal
  )
  return PMFExperienceTrace(
    schemaVersion: 1,
    scenario: PMFExperienceScenario(
      seed: "scenario-seed",
      personaSummary: "Hands-on operator",
      task: "Evaluate reporting workflow"
    ),
    initialState: initialState,
    turns: terminal
      ? [
        PMFExperienceTurn(
          index: 0,
          action: PMFExperienceAction(id: "provide_requested_input"),
          state: terminalState,
          allowedNextActions: [],
          eventLog: ["turn:0:provide_requested_input"]
        )
      ]
      : [],
    allowedNextActions: terminal ? [] : makeAllowedActions(),
    terminalStatus: terminal ? .completed : .inProgress,
    eventLog: terminal ? ["scenario_seed:scenario-seed", "completed"] : ["scenario_seed:scenario-seed"]
  )
}

private func makeAllowedActions() -> [PMFExperienceAllowedAction] {
  [
    PMFExperienceAllowedAction(
      id: "inspect_value_prop",
      label: "Inspect value proposition",
      description: "Read what product value the app claims to provide.",
      paramsSchema: .object(["type": .string("object")])
    ),
    PMFExperienceAllowedAction(
      id: "start_core_workflow",
      label: "Start core workflow",
      description: "Try the main workflow exposed by the app.",
      paramsSchema: .object(["type": .string("object")])
    ),
  ]
}

private func validFeedbackJSON(replacements: [String: String] = [:]) -> String {
  var json = """
    {
      "valueScore": 3,
      "clarityScore": 2,
      "trustScore": 3,
      "switchLikelihood": 2,
      "payLikelihood": 1,
      "taskOutcome": "partial",
      "topObjection": "I still cannot tell how this replaces my current spreadsheet.",
      "missingCapability": "A concrete import or reporting example.",
      "momentOfDelight": null,
      "momentOfConfusion": "The first screen says ready but not ready for what.",
      "verdict": "not_yet",
      "summary": "The promise is plausible, but the experience does not prove value quickly."
    }
    """
  for (original, replacement) in replacements {
    json = json.replacingOccurrences(of: original, with: replacement)
  }
  return json
}
