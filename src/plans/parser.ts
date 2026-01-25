import * as fs from 'fs';
import matter from 'gray-matter';

export type PlanStatus = 'pending' | 'in_progress' | 'completed' | 'blocked';
export type PlanPriority = 'high' | 'medium' | 'low';

export interface Plan {
  path: string;
  title: string;
  status: PlanStatus;
  priority: PlanPriority;
  dependencies: string[];
  description: string;
  acceptanceCriteria: string[];
  raw: string;
}

interface PlanFrontmatter {
  title?: string;
  status?: string;
  priority?: string;
  dependencies?: string[];
}

/**
 * Parse a plan markdown file into a structured Plan object
 */
export function parsePlan(filePath: string): Plan {
  const content = fs.readFileSync(filePath, 'utf-8');
  const { data: frontmatter, content: body } = matter(content) as {
    data: PlanFrontmatter;
    content: string;
  };

  // Extract title from frontmatter or first heading
  let title = frontmatter.title || '';
  if (!title) {
    const titleMatch = body.match(/^#\s+(?:Plan:\s*)?(.+)$/m);
    if (titleMatch) {
      title = titleMatch[1].trim();
    } else {
      title = filePath.split('/').pop()?.replace('.md', '') || 'Untitled';
    }
  }

  // Parse status from frontmatter or body
  let status: PlanStatus = 'pending';
  if (frontmatter.status) {
    status = normalizeStatus(frontmatter.status);
  } else {
    const statusMatch = body.match(/^##\s*Status\s*\n+([^\n#]+)/mi);
    if (statusMatch) {
      status = normalizeStatus(statusMatch[1].trim());
    }
  }

  // Parse priority
  let priority: PlanPriority = 'medium';
  if (frontmatter.priority) {
    priority = normalizePriority(frontmatter.priority);
  } else {
    const priorityMatch = body.match(/^##\s*Priority\s*\n+([^\n#]+)/mi);
    if (priorityMatch) {
      priority = normalizePriority(priorityMatch[1].trim());
    }
  }

  // Parse dependencies
  let dependencies: string[] = frontmatter.dependencies || [];
  if (dependencies.length === 0) {
    const depsMatch = body.match(/^##\s*Dependencies\s*\n+([\s\S]*?)(?=\n##|\n$|$)/mi);
    if (depsMatch) {
      dependencies = depsMatch[1]
        .split('\n')
        .map(line => line.replace(/^[-*]\s*/, '').trim())
        .filter(line => line.length > 0);
    }
  }

  // Parse description
  let description = '';
  const descMatch = body.match(/^##\s*Description\s*\n+([\s\S]*?)(?=\n##|$)/mi);
  if (descMatch) {
    description = descMatch[1].trim();
  }

  // Parse acceptance criteria
  const acceptanceCriteria: string[] = [];
  const acMatch = body.match(/^##\s*Acceptance\s*Criteria\s*\n+([\s\S]*?)(?=\n##|$)/mi);
  if (acMatch) {
    const lines = acMatch[1].split('\n');
    for (const line of lines) {
      const criterionMatch = line.match(/^[-*]\s*\[[ x]\]\s*(.+)$/i);
      if (criterionMatch) {
        acceptanceCriteria.push(criterionMatch[1].trim());
      }
    }
  }

  return {
    path: filePath,
    title,
    status,
    priority,
    dependencies,
    description,
    acceptanceCriteria,
    raw: content,
  };
}

function normalizeStatus(status: string): PlanStatus {
  const normalized = status.toLowerCase().trim();
  if (normalized === 'pending' || normalized === 'in_progress' ||
      normalized === 'completed' || normalized === 'blocked') {
    return normalized;
  }
  if (normalized === 'in-progress' || normalized === 'in progress') {
    return 'in_progress';
  }
  if (normalized === 'done' || normalized === 'complete') {
    return 'completed';
  }
  return 'pending';
}

function normalizePriority(priority: string): PlanPriority {
  const normalized = priority.toLowerCase().trim();
  if (normalized === 'high' || normalized === 'medium' || normalized === 'low') {
    return normalized;
  }
  return 'medium';
}

/**
 * Update a plan's status in its file
 */
export function updatePlanStatus(filePath: string, newStatus: PlanStatus): void {
  const content = fs.readFileSync(filePath, 'utf-8');
  const { data: frontmatter, content: body } = matter(content);

  // If frontmatter has status, update it there
  if (frontmatter.status !== undefined) {
    frontmatter.status = newStatus;
    const newContent = matter.stringify(body, frontmatter);
    fs.writeFileSync(filePath, newContent, 'utf-8');
    return;
  }

  // Otherwise update in body
  const updated = content.replace(
    /^(##\s*Status\s*\n+)([^\n#]+)/mi,
    `$1${newStatus}`
  );

  if (updated !== content) {
    fs.writeFileSync(filePath, updated, 'utf-8');
  }
}
