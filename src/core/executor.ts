import * as path from 'path';
import { PlanNode } from '../plans/tree.js';
import { updatePlanStatus } from '../plans/parser.js';
import { invokeClaude, ClaudeResponse } from '../utils/claude.js';
import { logger } from '../utils/logger.js';

export interface ExecutionContext {
  northContent: string;
  southContent: string;
  architectureContent: string;
  projectRoot: string;
  compassDir: string;
}

export interface ExecutionResult {
  success: boolean;
  output: string;
  decomposition?: DecompositionSignal;
  error?: string;
}

export interface DecompositionSignal {
  reason: string;
  suggestedSubPlans: string[];
}

const DECOMPOSITION_MARKER = '<<<DECOMPOSITION_NEEDED>>>';

/**
 * Execute a plan using Claude Code CLI
 */
export async function executePlan(
  plan: PlanNode,
  context: ExecutionContext
): Promise<ExecutionResult> {
  logger.info('Executing plan', { title: plan.plan.title, path: plan.plan.path });

  // Update plan status to in_progress
  updatePlanStatus(plan.plan.path, 'in_progress');
  plan.plan.status = 'in_progress';

  const prompt = buildExecutionPrompt(plan, context);

  // Execute via Claude Code CLI
  // Explicitly disallow editing .compass directory
  const response = await invokeClaude({
    prompt,
    cwd: context.projectRoot,
    timeout: 10 * 60 * 1000, // 10 minutes for execution
    skipPermissions: true, // Headless operation requires bypassing permission prompts
  });

  if (!response.success) {
    logger.error('Plan execution failed', {
      plan: plan.plan.title,
      error: response.error,
    });

    // Keep status as in_progress for investigation
    return {
      success: false,
      output: response.output,
      error: response.error,
    };
  }

  // Check for decomposition signal
  const decomposition = parseDecompositionSignal(response.output);
  if (decomposition) {
    logger.info('Plan requires decomposition', {
      plan: plan.plan.title,
      suggestedSubPlans: decomposition.suggestedSubPlans,
    });

    // Revert status to pending (decomposition is not failure)
    updatePlanStatus(plan.plan.path, 'pending');
    plan.plan.status = 'pending';

    return {
      success: true,
      output: response.output,
      decomposition,
    };
  }

  // Verify the execution
  const verification = await verifyExecution(plan, context, response.output);

  if (verification.verified) {
    logger.info('Plan completed successfully', { plan: plan.plan.title });
    updatePlanStatus(plan.plan.path, 'completed');
    plan.plan.status = 'completed';

    return {
      success: true,
      output: response.output + '\n\n--- Verification ---\n' + verification.output,
    };
  } else {
    logger.warn('Plan execution failed verification', {
      plan: plan.plan.title,
      verification: verification.output,
    });

    // Keep as in_progress for investigation
    return {
      success: false,
      output: response.output,
      error: `Verification failed: ${verification.output}`,
    };
  }
}

function buildExecutionPrompt(plan: PlanNode, context: ExecutionContext): string {
  const compassRelative = path.relative(context.projectRoot, context.compassDir);

  return `You are executing a specific implementation plan for this project.

## CRITICAL RULES
1. DO NOT modify any files in the \`${compassRelative}/\` directory
2. DO NOT create new plan files or modify existing plans
3. Only modify project source code, configuration, and documentation outside of \`${compassRelative}/\`
4. If this plan is too complex and needs to be broken down, respond with:
   ${DECOMPOSITION_MARKER}
   REASON: [why this needs decomposition]
   SUBPLANS:
   - [subplan 1 title]
   - [subplan 2 title]
   ...

## Project Goals (from NORTH.md)
${context.northContent}

## Anti-patterns to Avoid (from SOUTH.md)
${context.southContent}

## Current Architecture
${context.architectureContent || 'No architecture documentation yet.'}

## Plan to Execute
**Title:** ${plan.plan.title}
**Path:** ${plan.plan.path}

**Description:**
${plan.plan.description || 'No description provided'}

**Acceptance Criteria:**
${plan.plan.acceptanceCriteria.map(c => `- [ ] ${c}`).join('\n') || 'None specified'}

**Full Plan Content:**
${plan.plan.raw}

## Instructions
1. Implement the changes described in this plan
2. Ensure your changes align with NORTH.md goals
3. Avoid patterns mentioned in SOUTH.md
4. Update any relevant documentation (outside .compass/)
5. If the plan is too complex, signal decomposition as described above

Begin implementation now.`;
}

function parseDecompositionSignal(output: string): DecompositionSignal | null {
  if (!output.includes(DECOMPOSITION_MARKER)) {
    return null;
  }

  const markerIndex = output.indexOf(DECOMPOSITION_MARKER);
  const afterMarker = output.slice(markerIndex + DECOMPOSITION_MARKER.length);

  // Parse reason
  const reasonMatch = afterMarker.match(/REASON:\s*(.+?)(?=SUBPLANS:|$)/is);
  const reason = reasonMatch ? reasonMatch[1].trim() : 'No reason provided';

  // Parse subplans
  const subplansMatch = afterMarker.match(/SUBPLANS:\s*([\s\S]+)/i);
  const suggestedSubPlans: string[] = [];

  if (subplansMatch) {
    const lines = subplansMatch[1].split('\n');
    for (const line of lines) {
      const planMatch = line.match(/^[-*]\s*(.+)$/);
      if (planMatch) {
        suggestedSubPlans.push(planMatch[1].trim());
      }
    }
  }

  return {
    reason,
    suggestedSubPlans,
  };
}

interface VerificationResult {
  verified: boolean;
  output: string;
}

async function verifyExecution(
  plan: PlanNode,
  context: ExecutionContext,
  executionOutput: string
): Promise<VerificationResult> {
  const prompt = `You are verifying that a plan was executed correctly.

## Project Goals (NORTH.md)
${context.northContent}

## Anti-patterns to Avoid (SOUTH.md)
${context.southContent}

## Plan That Was Executed
**Title:** ${plan.plan.title}

**Acceptance Criteria:**
${plan.plan.acceptanceCriteria.map(c => `- ${c}`).join('\n') || 'None specified'}

## Execution Output
${executionOutput.slice(0, 5000)}${executionOutput.length > 5000 ? '\n...[truncated]' : ''}

## Instructions
Verify that:
1. The execution appears to have completed the plan's objectives
2. The changes align with NORTH.md goals
3. No SOUTH.md anti-patterns were introduced

Respond with EXACTLY this format:
VERIFIED: [yes/no]
SUMMARY: [brief summary of what was done]
ISSUES: [any concerns, or "none"]`;

  const response = await invokeClaude({
    prompt,
    cwd: context.projectRoot,
    timeout: 60000,
  });

  if (!response.success) {
    return {
      verified: false,
      output: `Verification failed: ${response.error}`,
    };
  }

  const verifiedMatch = response.output.match(/VERIFIED:\s*(yes|no)/i);
  const verified = verifiedMatch ? verifiedMatch[1].toLowerCase() === 'yes' : false;

  return {
    verified,
    output: response.output,
  };
}

/**
 * Create sub-plans from decomposition signal
 */
export function createSubPlansContent(
  parentPlan: PlanNode,
  decomposition: DecompositionSignal
): Map<string, string> {
  const subPlans = new Map<string, string>();

  decomposition.suggestedSubPlans.forEach((title, index) => {
    const fileName = `plan-${index + 1}.md`;
    const content = `# Plan: ${title}

## Status
pending

## Priority
${parentPlan.plan.priority}

## Dependencies
${index > 0 ? `- ./plan-${index}.md` : ''}

## Description
Sub-plan decomposed from parent plan: ${parentPlan.plan.title}

Reason for decomposition: ${decomposition.reason}

## Acceptance Criteria
- [ ] Complete implementation of: ${title}
`;

    subPlans.set(fileName, content);
  });

  return subPlans;
}
