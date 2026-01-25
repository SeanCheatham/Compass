export interface CompassDiffResult {
  hasDiff: boolean;
  isFirstRun: boolean;
  currentContent: string;
  shadowContent: string | null;
  diffSummary?: string;
}

export function detectCompassDiff(
  currentContent: string,
  shadowContent: string | null
): CompassDiffResult {
  if (shadowContent === null) {
    return {
      hasDiff: false,
      isFirstRun: true,
      currentContent,
      shadowContent: null,
    };
  }

  const hasDiff = currentContent !== shadowContent;

  return {
    hasDiff,
    isFirstRun: false,
    currentContent,
    shadowContent,
    diffSummary: hasDiff
      ? generateDiffSummary(currentContent, shadowContent)
      : undefined,
  };
}

function generateDiffSummary(current: string, shadow: string): string {
  const currentLines = current.split("\n");
  const shadowLines = shadow.split("\n");

  const currentSet = new Set(currentLines);
  const shadowSet = new Set(shadowLines);

  const added = currentLines.filter((l) => !shadowSet.has(l)).length;
  const removed = shadowLines.filter((l) => !currentSet.has(l)).length;

  return `${added} lines added, ${removed} lines removed`;
}
