import Foundation

/// Curated starter briefs for the Brief tab "Random idea" action.
///
/// Ideas stay small enough for a Compass-generated Rust `cli` / `macos` /
/// `server` scaffold so a new project can try the factory loop without inventing
/// product intent by hand.
public enum ProjectBriefIdeaGenerator {
  public static func random<G: RandomNumberGenerator>(
    using generator: inout G
  ) -> ProjectBrief {
    precondition(!catalog.isEmpty)
    let index = Int.random(in: 0..<catalog.count, using: &generator)
    return catalog[index]()
  }

  public static func random() -> ProjectBrief {
    var generator = SystemRandomNumberGenerator()
    return random(using: &generator)
  }

  /// Count of curated ideas (for tests / diagnostics).
  public static var catalogCount: Int { catalog.count }

  /// Materialize every curated idea (fresh requirement IDs each call).
  public static func allIdeas() -> [ProjectBrief] {
    catalog.map { $0() }
  }

  // Closures so each roll gets fresh requirement IDs.
  private static let catalog: [() -> ProjectBrief] = [
    {
      brief(
        audience: "People who forget to drink water at their desk",
        problem: "Hydration reminders are either naggy notifications or easy to ignore entirely.",
        requirements: [
          ("Show today's water goal and progress at a glance", .ux),
          ("Log a drink with one click or a short CLI command", .behavior),
          ("Keep all history on-device with no account required", .constraint),
        ]
      )
    },
    {
      brief(
        audience: "Indie developers shipping side projects alone",
        problem: "It's hard to remember which launch checklist items are still open before a release.",
        requirements: [
          ("Maintain a reusable release checklist with checkable items", .behavior),
          ("Export a markdown summary of remaining blockers", .behavior),
          ("Surface incomplete items prominently in the UI", .ux),
        ]
      )
    },
    {
      brief(
        audience: "Home cooks who meal-prep on Sundays",
        problem: "Leftover ingredients go unused because recipes aren't matched to what's already bought.",
        requirements: [
          ("Accept a pantry list and suggest 2–3 meals that use those items", .behavior),
          ("Show which leftover ingredients each meal consumes", .ux),
          ("Work fully offline from local data", .constraint),
        ]
      )
    },
    {
      brief(
        audience: "Writers drafting short posts",
        problem: "First drafts stall because blank pages feel unbounded and editing starts too early.",
        requirements: [
          ("Start a timed freewrite session with a visible countdown", .behavior),
          ("Lock editing until the timer ends, then unlock for revision", .behavior),
          ("Save sessions locally with word count", .nonfunctional),
        ]
      )
    },
    {
      brief(
        audience: "People tracking a small daily habit",
        problem: "Streak apps bury the habit under social features and cloud accounts.",
        requirements: [
          ("Mark today complete with a single action", .behavior),
          ("Show the current streak and calendar of recent days", .ux),
          ("Store streaks on-device only", .constraint),
        ]
      )
    },
    {
      brief(
        audience: "Parents packing school bags the night before",
        problem: "Recurring items (lunch, forms, gear) get forgotten on busy weeknights.",
        requirements: [
          ("Define weekday packing lists with reusable items", .behavior),
          ("Check off items for tomorrow's bag", .behavior),
          ("Highlight unchecked required items", .ux),
        ]
      )
    },
    {
      brief(
        audience: "Musicians learning songs",
        problem: "Practice sessions drift without a clear loop of sections to focus on.",
        requirements: [
          ("Split a song into named practice sections", .behavior),
          ("Track last practiced date and confidence per section", .behavior),
          ("Suggest the next section to practice", .ux),
        ]
      )
    },
    {
      brief(
        audience: "People managing a shared household shopping list",
        problem: "Paper lists and group chats lose items and duplicate purchases.",
        requirements: [
          ("Add, check off, and clear shopping items quickly", .behavior),
          ("Group items by aisle or category", .ux),
          ("Persist the list locally between launches", .nonfunctional),
        ]
      )
    },
    {
      brief(
        audience: "Students reviewing flashcards",
        problem: "Deck apps are heavy; a tiny spaced-repetition loop for one subject is enough.",
        requirements: [
          ("Create cards with front/back text", .behavior),
          ("Quiz with again/good ratings that schedule the next review", .behavior),
          ("Show how many cards are due today", .ux),
        ]
      )
    },
    {
      brief(
        audience: "Freelancers sending simple invoices",
        problem: "Spreadsheet invoices are error-prone and look inconsistent.",
        requirements: [
          ("Create an invoice with client, line items, and total", .behavior),
          ("Export a plain-text or markdown invoice", .behavior),
          ("Keep a local history of past invoices", .nonfunctional),
        ]
      )
    },
    {
      brief(
        audience: "People who want a calmer personal reading list",
        problem: "Bookmark piles grow without a clear next book to open.",
        requirements: [
          ("Add books with title, author, and status (want/reading/done)", .behavior),
          ("Pick a random unread book when asked", .behavior),
          ("Show counts by status on the home view", .ux),
        ]
      )
    },
    {
      brief(
        audience: "Runners logging easy outdoor miles",
        problem: "Full fitness suites are overkill for jotting distance, time, and how it felt.",
        requirements: [
          ("Log a run with distance, duration, and a short note", .behavior),
          ("Show recent runs and a weekly mileage total", .ux),
          ("Never require a wearable or cloud account", .constraint),
        ]
      )
    },
    {
      brief(
        audience: "Teams that need a tiny internal status API",
        problem: "Spreading service health across chat bots and ad-hoc scripts makes outages hard to see.",
        requirements: [
          ("Expose a /status HTTP endpoint with a clear healthy/unhealthy payload", .behavior),
          ("Allow operators to flip a maintenance flag via a protected route", .behavior),
          ("Keep the service runnable as a single local binary with no external DB", .constraint),
        ]
      )
    },
    {
      brief(
        audience: "Developers who want a local webhook receiver while building integrations",
        problem: "Public tunnel tools are heavy when you only need to inspect POSTed JSON on localhost.",
        requirements: [
          ("Accept POST /hooks and store the last N payloads in memory", .behavior),
          ("List recent payloads via GET /hooks", .behavior),
          ("Provide a CLI that prints the latest payload as JSON", .behavior),
        ]
      )
    },
  ]

  private static func brief(
    audience: String,
    problem: String,
    requirements: [(String, ProductRequirementKind)]
  ) -> ProjectBrief {
    ProjectBrief(
      audience: audience,
      problem: problem,
      productRequirements: requirements.map { text, kind in
        ProductRequirement(text: text, kind: kind)
      }
    )
  }
}
