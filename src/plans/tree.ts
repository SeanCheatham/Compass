import * as fs from 'fs';
import * as path from 'path';
import { glob } from 'glob';
import { parsePlan, Plan, PlanStatus } from './parser.js';
import { logger } from '../utils/logger.js';

export interface PlanNode {
  plan: Plan;
  children: PlanNode[];
  parent: PlanNode | null;
  isLeaf: boolean;
}

export interface PlanTree {
  root: PlanNode[];
  allPlans: Map<string, PlanNode>;
}

/**
 * Build a plan tree from the plans directory
 */
export async function buildPlanTree(plansDir: string): Promise<PlanTree> {
  const allPlans = new Map<string, PlanNode>();
  const root: PlanNode[] = [];

  if (!fs.existsSync(plansDir)) {
    logger.warn('Plans directory does not exist', { plansDir });
    return { root, allPlans };
  }

  // Find all plan markdown files
  const planFiles = await glob('**/*.md', { cwd: plansDir });
  logger.debug('Found plan files', { count: planFiles.length, files: planFiles });

  // Parse all plans first
  for (const file of planFiles) {
    const fullPath = path.join(plansDir, file);
    try {
      const plan = parsePlan(fullPath);
      const node: PlanNode = {
        plan,
        children: [],
        parent: null,
        isLeaf: true,
      };
      allPlans.set(fullPath, node);
    } catch (err) {
      logger.error('Failed to parse plan file', { file, error: (err as Error).message });
    }
  }

  // Build tree structure based on directory hierarchy
  for (const [planPath, node] of allPlans) {
    const relativePath = path.relative(plansDir, planPath);
    const parts = relativePath.split(path.sep);

    if (parts.length === 1) {
      // Root level plan
      root.push(node);
    } else {
      // Nested plan - find parent
      // Parent is the plan file matching the directory name
      const parentDirName = parts[parts.length - 2];
      const parentFileName = `${parentDirName}.md`;

      // Look for parent at the level above
      const parentParts = parts.slice(0, -2);
      const parentPath = path.join(plansDir, ...parentParts, parentFileName);

      const parentNode = allPlans.get(parentPath);
      if (parentNode) {
        parentNode.children.push(node);
        parentNode.isLeaf = false;
        node.parent = parentNode;
      } else {
        // No explicit parent found, add to root
        root.push(node);
      }
    }
  }

  // Sort children by priority
  const sortByPriority = (nodes: PlanNode[]): void => {
    const priorityOrder: Record<string, number> = { high: 0, medium: 1, low: 2 };
    nodes.sort((a, b) => {
      const aPriority = priorityOrder[a.plan.priority] ?? 1;
      const bPriority = priorityOrder[b.plan.priority] ?? 1;
      return aPriority - bPriority;
    });
  };

  sortByPriority(root);
  for (const node of allPlans.values()) {
    if (node.children.length > 0) {
      sortByPriority(node.children);
    }
  }

  logger.info('Built plan tree', { totalPlans: allPlans.size, rootCount: root.length });
  return { root, allPlans };
}

/**
 * Get all leaf plans (plans that can be executed)
 */
export function getLeafPlans(tree: PlanTree): PlanNode[] {
  const leaves: PlanNode[] = [];

  for (const node of tree.allPlans.values()) {
    if (node.isLeaf) {
      leaves.push(node);
    }
  }

  return leaves;
}

/**
 * Get all executable leaf plans (pending and not blocked by dependencies)
 */
export function getExecutableLeaves(tree: PlanTree): PlanNode[] {
  const leaves = getLeafPlans(tree);

  return leaves.filter(node => {
    // Must be pending
    if (node.plan.status !== 'pending') {
      return false;
    }

    // Check dependencies
    for (const dep of node.plan.dependencies) {
      const depPath = path.isAbsolute(dep) ? dep : path.resolve(path.dirname(node.plan.path), dep);
      const depNode = tree.allPlans.get(depPath);
      if (depNode && depNode.plan.status !== 'completed') {
        return false;
      }
    }

    return true;
  });
}

/**
 * Format plan tree for display
 */
export function formatTreeForDisplay(tree: PlanTree): string {
  const lines: string[] = [];

  const formatNode = (node: PlanNode, indent: string, isLast: boolean): void => {
    const prefix = indent + (isLast ? '└── ' : '├── ');
    const statusIcon = getStatusIcon(node.plan.status);
    const leafIcon = node.isLeaf ? '📄' : '📁';

    lines.push(`${prefix}${leafIcon} ${statusIcon} ${node.plan.title}`);

    const childIndent = indent + (isLast ? '    ' : '│   ');
    node.children.forEach((child, i) => {
      formatNode(child, childIndent, i === node.children.length - 1);
    });
  };

  tree.root.forEach((node, i) => {
    formatNode(node, '', i === tree.root.length - 1);
  });

  return lines.join('\n');
}

function getStatusIcon(status: PlanStatus): string {
  switch (status) {
    case 'pending':
      return '⏳';
    case 'in_progress':
      return '🔄';
    case 'completed':
      return '✅';
    case 'blocked':
      return '🚫';
  }
}

/**
 * Get summary statistics for the plan tree
 */
export function getTreeStats(tree: PlanTree): {
  total: number;
  pending: number;
  inProgress: number;
  completed: number;
  blocked: number;
  leaves: number;
} {
  let pending = 0;
  let inProgress = 0;
  let completed = 0;
  let blocked = 0;
  let leaves = 0;

  for (const node of tree.allPlans.values()) {
    switch (node.plan.status) {
      case 'pending':
        pending++;
        break;
      case 'in_progress':
        inProgress++;
        break;
      case 'completed':
        completed++;
        break;
      case 'blocked':
        blocked++;
        break;
    }
    if (node.isLeaf) {
      leaves++;
    }
  }

  return {
    total: tree.allPlans.size,
    pending,
    inProgress,
    completed,
    blocked,
    leaves,
  };
}
