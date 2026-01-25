import { spawn } from 'child_process';
import { logger } from './logger.js';

export interface ClaudeResponse {
  success: boolean;
  output: string;
  error?: string;
  exitCode: number | null;
}

export interface ClaudeOptions {
  prompt: string;
  cwd?: string;
  timeout?: number;
  allowedTools?: string[];
  disallowedTools?: string[];
  skipPermissions?: boolean;
}

const DEFAULT_TIMEOUT = 5 * 60 * 1000; // 5 minutes

export async function invokeClaude(options: ClaudeOptions): Promise<ClaudeResponse> {
  const { prompt, cwd = process.cwd(), timeout = DEFAULT_TIMEOUT } = options;

  logger.debug('Invoking Claude Code CLI', { cwd, promptLength: prompt.length });

  return new Promise((resolve) => {
    const args = ['--print', '--verbose'];

    // Skip permission prompts for headless operation
    if (options.skipPermissions) {
      args.push('--dangerously-skip-permissions');
    }

    // Add tool restrictions if specified
    if (options.allowedTools && options.allowedTools.length > 0) {
      args.push('--allowedTools', options.allowedTools.join(','));
    }
    if (options.disallowedTools && options.disallowedTools.length > 0) {
      args.push('--disallowedTools', options.disallowedTools.join(','));
    }

    const child = spawn('claude', args, {
      cwd,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    // Write prompt to stdin and close to signal EOF
    child.stdin.write(prompt);
    child.stdin.end();

    let stdout = '';
    let stderr = '';
    let stdoutLineBuffer = '';

    child.stdout.on('data', (data: Buffer) => {
      const chunk = data.toString();
      stdout += chunk;

      // Buffer and log complete lines
      stdoutLineBuffer += chunk;
      const lines = stdoutLineBuffer.split('\n');
      // Keep the last incomplete line in the buffer
      stdoutLineBuffer = lines.pop() || '';
      for (const line of lines) {
        logger.info('Claude output', { line });
      }
    });

    child.stderr.on('data', (data: Buffer) => {
      stderr += data.toString();
    });

    const timeoutId = setTimeout(() => {
      logger.warn('Claude CLI timed out, killing process');
      child.kill('SIGTERM');
      resolve({
        success: false,
        output: stdout,
        error: `Process timed out after ${timeout}ms`,
        exitCode: null,
      });
    }, timeout);

    child.on('error', (err) => {
      clearTimeout(timeoutId);
      logger.error('Claude CLI spawn error', { error: err.message });
      resolve({
        success: false,
        output: stdout,
        error: err.message,
        exitCode: null,
      });
    });

    child.on('close', (code) => {
      clearTimeout(timeoutId);
      // Flush any remaining buffered output
      if (stdoutLineBuffer) {
        logger.debug('Claude output', { line: stdoutLineBuffer });
      }
      const success = code === 0;
      if (success) {
        logger.debug('Claude CLI completed successfully');
      } else {
        logger.warn('Claude CLI exited with error', { code, stderr });
      }
      resolve({
        success,
        output: stdout,
        error: stderr || undefined,
        exitCode: code,
      });
    });
  });
}

/**
 * Invoke Claude with a specific system prompt context
 */
export async function invokeClaudeWithContext(
  systemContext: string,
  userPrompt: string,
  options?: Partial<ClaudeOptions>
): Promise<ClaudeResponse> {
  const fullPrompt = `${systemContext}\n\n---\n\n${userPrompt}`;
  return invokeClaude({
    prompt: fullPrompt,
    ...options,
  });
}
