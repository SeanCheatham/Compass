import { PlanNode, PlanTree, getExecutableLeaves, getTreeStats, formatTreeForDisplay } from './tree.js';
import { invokeClaude, ClaudeResponse } from '../utils/claude.js';
import { logger } from '../utils/logger.js';

export interface PrioritizerContext {
  northContent: string;
  southContent: string;
  recentlyCompleted: string[];
  tree: PlanTree;
}

export interface PrioritizationResult {
  selectedPlan: PlanNode | null;
  reasoning: string;
  response: ClaudeResponse;
}

/**
 * Use Claude to select the next plan to execute based on context
 */
export async function selectNextPlan(context: PrioritizerContext): Promise<PrioritizationResult> {
  const executableLeaves = getExecutableLeaves(context.tree);

  if (executableLeaves.length === 0) {
    logger.info('No executable plans available');
    return {
      selectedPlan: null,
      reasoning: 'No executable plans available (all completed, blocked, or in progress)',
      response: { success: true, output: '', exitCode: 0 },
    };
  }

  if (executableLeaves.length === 1) {
    logger.info('Only one executable plan available', { plan: executableLeaves[0].plan.title });
    return {
      selectedPlan: executableLeaves[0],
      reasoning: 'Only one executable plan available',
      response: { success: true, output: '', exitCode: 0 },
    };
  }

  // Build prompt for Claude to select the next plan
  const prompt = buildPrioritizationPrompt(context, executableLeaves);
  const response = await invokeClaude({ prompt, timeout: 60000 });

  if (!response.success) {
    logger.warn('Prioritizer Claude call failed, falling back to first executable plan', {
      error: response.error,
    });
    return {
      selectedPlan: executableLeaves[0],
      reasoning: 'Fell back to first plan due to Claude error',
      response,
    };
  }

  // Parse Claude's response to find selected plan
  const result = parseSelectionResponse(response.output, executableLeaves);

  return {
    ...result,
    response,
  };
}

function buildPrioritizationPrompt(context: PrioritizerContext, executableLeaves: PlanNode[]): string {
  const stats = getTreeStats(context.tree);
  const treeDisplay = formatTreeForDisplay(context.tree);

  const planOptions = executableLeaves.map((node, i) => {
    return `${i + 1}. **${node.plan.title}** (${node.plan.path})
   Priority: ${node.plan.priority}
   Description: ${node.plan.description || 'No description'}
   Acceptance Criteria: ${node.plan.acceptanceCriteria.length > 0 ? node.plan.acceptanceCriteria.join(', ') : 'None specified'}`;
  }).join('\n\n');

  const recentlyCompletedStr = context.recentlyCompleted.length > 0
    ? context.recentlyCompleted.join('\n- ')
    : 'None yet';

  return `You are a project prioritization assistant. Your task is to select the next plan to execute from a list of available plans.

## Project Goals (NORTH.md)
${context.northContent}

## Anti-patterns to Avoid (SOUTH.md)
${context.southContent}

## Current Plan Tree Status
Total plans: ${stats.total}
Completed: ${stats.completed}
In Progress: ${stats.inProgress}
Pending: ${stats.pending}
Blocked: ${stats.blocked}

Tree structure:
${treeDisplay}

## Recently Completed Plans
- ${recentlyCompletedStr}

## Available Plans to Execute
${planOptions}

## Instructions
Select the plan that should be executed next. Consider:
1. Alignment with project goals (NORTH.md)
2. Avoiding anti-patterns (SOUTH.md)
3. Plan priority (high > medium > low)
4. Dependencies and logical ordering
5. What was recently completed (build on momentum)

Respond with EXACTLY this format:
SELECTED: [plan number]
REASONING: [brief explanation]

Example:
SELECTED: 2
REASONING: This plan addresses a core feature needed before other plans can proceed.`;
}

function parseSelectionResponse(output: string, executableLeaves: PlanNode[]): {
  selectedPlan: PlanNode | null;
  reasoning: string;
} {
  // Try to parse the SELECTED: X format
  const selectedMatch = output.match(/SELECTED:\s*(\d+)/i);
  const reasoningMatch = output.match(/REASONING:\s*(.+?)(?:\n|$)/is);

  const reasoning = reasoningMatch ? reasoningMatch[1].trim() : 'No reasoning provided';

  if (selectedMatch) {
    const index = parseInt(selectedMatch[1], 10) - 1;
    if (index >= 0 && index < executableLeaves.length) {
      logger.info('Prioritizer selected plan', {
        plan: executableLeaves[index].plan.title,
        reasoning,
      });
      return {
        selectedPlan: executableLeaves[index],
        reasoning,
      };
    }
  }

  // Fallback: look for any mention of plan titles
  for (const node of executableLeaves) {
    if (output.includes(node.plan.title) || output.includes(node.plan.path)) {
      logger.info('Prioritizer selected plan (fuzzy match)', { plan: node.plan.title });
      return {
        selectedPlan: node,
        reasoning,
      };
    }
  }

  // Final fallback: return the first high-priority plan or just the first plan
  const highPriority = executableLeaves.find(n => n.plan.priority === 'high');
  const selected = highPriority || executableLeaves[0];

  logger.warn('Could not parse prioritizer response, falling back', {
    selectedPlan: selected.plan.title,
  });

  return {
    selectedPlan: selected,
    reasoning: `Fallback selection: ${reasoning}`,
  };
}
