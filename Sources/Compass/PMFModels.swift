import Foundation

struct ProductHypothesis: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var targetUser: String
  var jobToBeDone: String
  var pain: String
  var promise: String
  var currentAlternatives: [String]
  var successCriteria: [String]
  var pricingAssumptions: [String]
  var switchingAssumptions: [String]
  var knownRisks: [String]
  var createdAt: Double
  var updatedAt: Double

  init(
    id: String,
    title: String,
    targetUser: String,
    jobToBeDone: String,
    pain: String,
    promise: String,
    currentAlternatives: [String] = [],
    successCriteria: [String] = [],
    pricingAssumptions: [String] = [],
    switchingAssumptions: [String] = [],
    knownRisks: [String] = [],
    createdAt: Double,
    updatedAt: Double? = nil
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "hypothesis")
    self.title = Self.cleanedText(title, fallback: "Product hypothesis")
    self.targetUser = Self.cleanedText(targetUser, fallback: "Target user to validate")
    self.jobToBeDone = Self.cleanedText(jobToBeDone, fallback: "Complete the target job")
    self.pain = Self.cleanedText(pain, fallback: "Current workflow pain to validate")
    self.promise = Self.cleanedText(promise, fallback: "Product promise to test")
    self.currentAlternatives = Self.cleanedList(currentAlternatives)
    self.successCriteria = Self.cleanedList(successCriteria)
    self.pricingAssumptions = Self.cleanedList(pricingAssumptions)
    self.switchingAssumptions = Self.cleanedList(switchingAssumptions)
    self.knownRisks = Self.cleanedList(knownRisks)
    self.createdAt = createdAt
    self.updatedAt = updatedAt ?? createdAt
  }
}

struct PMFPersona: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var name: String
  var role: String
  var context: String
  var goals: [String]
  var constraints: [String]
  var currentWorkflow: String
  var skepticism: String
  var decisionCriteria: [String]
  var technicalComfort: String

  init(
    id: String,
    name: String,
    role: String,
    context: String,
    goals: [String] = [],
    constraints: [String] = [],
    currentWorkflow: String,
    skepticism: String,
    decisionCriteria: [String] = [],
    technicalComfort: String
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "persona")
    self.name = Self.cleanedText(name, fallback: "PMF persona")
    self.role = Self.cleanedText(role, fallback: "Target user")
    self.context = Self.cleanedText(context, fallback: "Evaluating the product in a real workflow")
    self.goals = Self.cleanedList(goals)
    self.constraints = Self.cleanedList(constraints)
    self.currentWorkflow = Self.cleanedText(
      currentWorkflow,
      fallback: "Uses an existing workflow and needs a reason to switch"
    )
    self.skepticism = Self.cleanedText(
      skepticism,
      fallback: "Wants concrete proof before trusting the product claim"
    )
    self.decisionCriteria = Self.cleanedList(decisionCriteria)
    self.technicalComfort = Self.cleanedText(technicalComfort, fallback: "moderate")
  }
}

struct PMFTask: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var situation: String
  var desiredOutcome: String
  var startingContext: String
  var successSignals: [String]
  var failureSignals: [String]
  var maxTurns: Int

  init(
    id: String,
    title: String,
    situation: String,
    desiredOutcome: String,
    startingContext: String,
    successSignals: [String] = [],
    failureSignals: [String] = [],
    maxTurns: Int
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "task")
    self.title = Self.cleanedText(title, fallback: "PMF task")
    self.situation = Self.cleanedText(situation, fallback: "Evaluate the product experience")
    self.desiredOutcome = Self.cleanedText(
      desiredOutcome,
      fallback: "Decide whether the product helps"
    )
    self.startingContext = Self.cleanedText(
      startingContext,
      fallback: "Start from the generated app's initial state"
    )
    self.successSignals = Self.cleanedList(successSignals)
    self.failureSignals = Self.cleanedList(failureSignals)
    self.maxTurns = max(1, maxTurns)
  }
}

struct PMFScenario: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var hypothesisID: String
  var personaID: String
  var taskID: String
  var seed: String
  var enabled: Bool
  var tags: [String]

  init(
    id: String,
    title: String,
    hypothesisID: String,
    personaID: String,
    taskID: String,
    seed: String,
    enabled: Bool = true,
    tags: [String] = []
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "scenario")
    self.title = Self.cleanedText(title, fallback: "PMF scenario")
    self.hypothesisID = Self.cleanedIdentifier(hypothesisID, fallback: "hypothesis")
    self.personaID = Self.cleanedIdentifier(personaID, fallback: "persona")
    self.taskID = Self.cleanedIdentifier(taskID, fallback: "task")
    self.seed = Self.cleanedIdentifier(seed, fallback: self.id)
    self.enabled = enabled
    self.tags = Self.cleanedList(tags)
  }
}

struct PMFScenarioCohort: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var title: String
  var scenarioIDs: [String]
  var enabled: Bool
  var tags: [String]

  init(
    id: String,
    title: String,
    scenarioIDs: [String],
    enabled: Bool = true,
    tags: [String] = []
  ) {
    self.id = Self.cleanedIdentifier(id, fallback: "cohort")
    self.title = Self.cleanedText(title, fallback: "PMF cohort")
    self.scenarioIDs = Self.cleanedList(scenarioIDs).map {
      Self.cleanedIdentifier($0, fallback: "scenario")
    }
    self.enabled = enabled
    self.tags = Self.cleanedList(tags)
  }
}

struct PMFConfig: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 1

  var schemaVersion: Int
  var hypotheses: [ProductHypothesis]
  var personas: [PMFPersona]
  var tasks: [PMFTask]
  var scenarios: [PMFScenario]
  var cohorts: [PMFScenarioCohort]

  static let empty = PMFConfig(
    hypotheses: [],
    personas: [],
    tasks: [],
    scenarios: [],
    cohorts: []
  )

  enum CodingKeys: String, CodingKey {
    case schemaVersion
    case hypotheses
    case personas
    case tasks
    case scenarios
    case cohorts
  }

  init(
    schemaVersion: Int = Self.supportedSchemaVersion,
    hypotheses: [ProductHypothesis],
    personas: [PMFPersona],
    tasks: [PMFTask],
    scenarios: [PMFScenario],
    cohorts: [PMFScenarioCohort] = []
  ) {
    self.schemaVersion = schemaVersion
    self.hypotheses = hypotheses
    self.personas = personas
    self.tasks = tasks
    self.scenarios = scenarios
    self.cohorts = cohorts
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion =
      try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
      ?? Self.supportedSchemaVersion
    guard schemaVersion == Self.supportedSchemaVersion else {
      throw PMFConfigError.unsupportedSchemaVersion(schemaVersion)
    }

    self.schemaVersion = schemaVersion
    hypotheses = try container.decodeIfPresent([ProductHypothesis].self, forKey: .hypotheses) ?? []
    personas = try container.decodeIfPresent([PMFPersona].self, forKey: .personas) ?? []
    tasks = try container.decodeIfPresent([PMFTask].self, forKey: .tasks) ?? []
    scenarios = try container.decodeIfPresent([PMFScenario].self, forKey: .scenarios) ?? []
    cohorts = try container.decodeIfPresent([PMFScenarioCohort].self, forKey: .cohorts) ?? []
  }

  var isEmpty: Bool {
    hypotheses.isEmpty && personas.isEmpty && tasks.isEmpty && scenarios.isEmpty && cohorts.isEmpty
  }

  static func seedDefaults(
    projectTitle: String,
    vision: String,
    now: Date = Date()
  ) -> PMFConfig {
    let timestamp = now.timeIntervalSince1970
    let title = projectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayTitle = title.isEmpty ? "Project" : title
    let slug = PMFModelText.slug(displayTitle, fallback: "project")
    let visionSummary =
      PMFModelText.firstMeaningfulLine(in: vision)
      ?? "\(displayTitle) should prove its product promise through a generated app experience."

    let hypothesis = ProductHypothesis(
      id: "\(slug)-initial-hypothesis",
      title: "\(displayTitle) initial product hypothesis",
      targetUser: "The target user described by the project vision.",
      jobToBeDone: visionSummary,
      pain: "The current workflow is costly enough that a simulated user should demand proof.",
      promise: "The generated app can make the target job clearer, faster, or safer.",
      currentAlternatives: [
        "Manual process",
        "Spreadsheet or notes workflow",
        "Existing niche tool or internal workaround",
      ],
      successCriteria: [
        "The persona can explain the product value in their own words.",
        "The persona sees a concrete workflow rather than only a claim.",
        "The persona names fewer unresolved switching objections after the task.",
      ],
      pricingAssumptions: [
        "Payment interest depends on proof of time saved or risk reduced."
      ],
      switchingAssumptions: [
        "Switching requires confidence that current alternatives are addressed."
      ],
      knownRisks: [
        "The experience may communicate a promise without proving a workflow.",
        "Personas may understand the app but still prefer their current alternative.",
      ],
      createdAt: timestamp
    )

    let personas = [
      PMFPersona(
        id: "\(slug)-operator",
        name: "Hands-on operator",
        role: "Primary user responsible for getting the job done",
        context: "Has limited patience for setup and compares every claim to daily work.",
        goals: [
          "Finish the task with fewer steps.",
          "See whether the app handles real operating detail.",
        ],
        constraints: [
          "Short evaluation window",
          "Cannot disrupt the current workflow without clear upside",
        ],
        currentWorkflow: "Uses a familiar manual process and asks teammates for missing context.",
        skepticism: "Dismisses vague value propositions and wants to see the workflow.",
        decisionCriteria: [
          "Time saved",
          "Reduced rework",
          "Confidence in the next action",
        ],
        technicalComfort: "moderate"
      ),
      PMFPersona(
        id: "\(slug)-buyer",
        name: "Budget owner",
        role: "Economic buyer deciding whether the change is worth funding",
        context: "Evaluates the product from expected impact, adoption risk, and switching cost.",
        goals: [
          "Understand the business outcome.",
          "Identify hidden implementation or training costs.",
        ],
        constraints: [
          "Needs credible ROI before sponsoring adoption",
          "Has seen similar tools overpromise",
        ],
        currentWorkflow: "Approves incremental improvements only when the proof is concrete.",
        skepticism: "Treats polished copy as unproven until tied to measurable outcomes.",
        decisionCriteria: [
          "Credible value proof",
          "Switching risk",
          "Team adoption likelihood",
        ],
        technicalComfort: "low"
      ),
      PMFPersona(
        id: "\(slug)-power-user",
        name: "Power user skeptic",
        role: "Experienced practitioner with a mature current workflow",
        context: "Knows edge cases and quickly notices missing capabilities.",
        goals: [
          "Test whether the app respects expert workflow constraints.",
          "Find whether it improves the current alternative enough to switch.",
        ],
        constraints: [
          "Already has an optimized workaround",
          "Needs control and transparency",
        ],
        currentWorkflow: "Combines existing tools, templates, and personal judgment.",
        skepticism: "Assumes the app is too shallow until it handles a realistic task.",
        decisionCriteria: [
          "Depth of workflow support",
          "Control over important details",
          "Clear advantage over the current workaround",
        ],
        technicalComfort: "high"
      ),
    ]

    let tasks = [
      PMFTask(
        id: "\(slug)-understand-promise",
        title: "Understand the value promise",
        situation: "The persona has just opened the generated app for the first time.",
        desiredOutcome: "Decide whether the product claim is relevant enough to keep exploring.",
        startingContext: "Start from the initial semantic app state.",
        successSignals: [
          "The persona can describe what problem the app solves.",
          "The persona sees why this could beat a current alternative.",
        ],
        failureSignals: [
          "The persona sees only generic copy.",
          "The persona cannot connect the promise to their own work.",
        ],
        maxTurns: 6
      ),
      PMFTask(
        id: "\(slug)-try-core-workflow",
        title: "Try the core workflow",
        situation: "The persona is willing to test whether the app can support the target job.",
        desiredOutcome: "Reach a concrete workflow outcome or name the blocker that prevents it.",
        startingContext: "Use the app's allowed semantic actions from the initial state.",
        successSignals: [
          "The persona completes or meaningfully advances the target job.",
          "The persona sees specific evidence of value.",
        ],
        failureSignals: [
          "The app cannot expose the intended workflow.",
          "The persona abandons because the next step is unclear.",
        ],
        maxTurns: 8
      ),
    ]

    let scenarios = personas.flatMap { persona in
      tasks.map { task in
        PMFScenario(
          id: "\(persona.id)-\(task.id)",
          title: "\(persona.name): \(task.title)",
          hypothesisID: hypothesis.id,
          personaID: persona.id,
          taskID: task.id,
          seed: "\(persona.id)-\(task.id)",
          tags: ["seeded", task.id]
        )
      }
    }

    return PMFConfig(
      hypotheses: [hypothesis],
      personas: personas,
      tasks: tasks,
      scenarios: scenarios,
      cohorts: [
        PMFScenarioCohort(
          id: "\(slug)-starter-cohort",
          title: "\(displayTitle) starter PMF cohort",
          scenarioIDs: scenarios.map(\.id),
          tags: ["seeded", "starter"]
        )
      ]
    )
  }
}

enum PMFConfigError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported PMF config schema version \(version)."
    }
  }
}

private enum PMFModelText {
  static func firstMeaningfulLine(in text: String) -> String? {
    text
      .split(whereSeparator: \.isNewline)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }

  static func slug(_ value: String, fallback: String) -> String {
    let normalized =
      value
      .lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return String((normalized.isEmpty ? fallback : normalized).prefix(64))
  }
}

private protocol PMFModelCleanable {}

extension PMFModelCleanable {
  static func cleanedText(_ value: String, fallback: String) -> String {
    let cleaned = StringUtils.boundedText(value, limit: Int.max)
    return cleaned.isEmpty ? fallback : cleaned
  }

  static func cleanedList(_ values: [String]) -> [String] {
    values
      .map { StringUtils.boundedText($0, limit: Int.max) }
      .filter { !$0.isEmpty }
  }

  static func cleanedIdentifier(_ value: String, fallback: String) -> String {
    PMFModelText.slug(value, fallback: fallback)
  }
}

extension ProductHypothesis: PMFModelCleanable {}
extension PMFPersona: PMFModelCleanable {}
extension PMFTask: PMFModelCleanable {}
extension PMFScenario: PMFModelCleanable {}
extension PMFScenarioCohort: PMFModelCleanable {}
