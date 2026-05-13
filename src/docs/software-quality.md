# Software Quality

Compass should bias toward production-quality increments, even when a plan is small. Prefer changes that are easy to verify, easy to revert, and easy for a future agent or human to understand.

## Implementation Standards

- Keep the change scoped to the plan and the surrounding ownership boundary.
- Preserve existing architecture and local conventions unless the plan explicitly asks for a redesign.
- Prefer typed, structured APIs over ad hoc string parsing when the platform gives you a reasonable option.
- Add abstractions only when they remove real complexity or match a pattern already present in the codebase.
- Treat prompt text, shell commands, file paths, and generated code as user-controlled input unless proven otherwise.

## Review Checklist

- Does the implementation satisfy the exact plan without unrelated cleanup?
- Are failure modes explicit and visible to the runner or user?
- Are state writes durable and recoverable?
- Are external commands run with shell-free APIs unless a shell is intentionally required?
- Does the verification command prove the important behavior, not merely compile nearby code?
