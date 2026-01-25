import * as fs from 'fs';
import * as path from 'path';
import chalk from 'chalk';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  message: string;
  context?: Record<string, unknown>;
}

export class Logger {
  private logFile: string | null = null;
  private minLevel: LogLevel = 'info';

  private levelPriority: Record<LogLevel, number> = {
    debug: 0,
    info: 1,
    warn: 2,
    error: 3,
  };

  constructor(options?: { logFile?: string; minLevel?: LogLevel }) {
    if (options?.logFile) {
      this.logFile = options.logFile;
      const logDir = path.dirname(this.logFile);
      if (!fs.existsSync(logDir)) {
        fs.mkdirSync(logDir, { recursive: true });
      }
    }
    if (options?.minLevel) {
      this.minLevel = options.minLevel;
    }
  }

  setLogFile(logFile: string): void {
    this.logFile = logFile;
    const logDir = path.dirname(this.logFile);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
  }

  private shouldLog(level: LogLevel): boolean {
    return this.levelPriority[level] >= this.levelPriority[this.minLevel];
  }

  private formatEntry(entry: LogEntry): string {
    let line = `[${entry.timestamp}] ${entry.level.toUpperCase()}: ${entry.message}`;
    if (entry.context) {
      line += ` ${JSON.stringify(entry.context)}`;
    }
    return line;
  }

  private writeToFile(entry: LogEntry): void {
    if (this.logFile) {
      const line = this.formatEntry(entry) + '\n';
      fs.appendFileSync(this.logFile, line, 'utf-8');
    }
  }

  private log(level: LogLevel, message: string, context?: Record<string, unknown>): void {
    if (!this.shouldLog(level)) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      context,
    };

    this.writeToFile(entry);

    // Console output with colors
    const prefix = `[${entry.timestamp.split('T')[1].split('.')[0]}]`;
    let coloredLevel: string;

    switch (level) {
      case 'debug':
        coloredLevel = chalk.gray('DEBUG');
        break;
      case 'info':
        coloredLevel = chalk.blue('INFO');
        break;
      case 'warn':
        coloredLevel = chalk.yellow('WARN');
        break;
      case 'error':
        coloredLevel = chalk.red('ERROR');
        break;
    }

    let output = `${chalk.dim(prefix)} ${coloredLevel}: ${message}`;
    if (context) {
      output += ` ${chalk.dim(JSON.stringify(context))}`;
    }

    if (level === 'error') {
      console.error(output);
    } else {
      console.log(output);
    }
  }

  debug(message: string, context?: Record<string, unknown>): void {
    this.log('debug', message, context);
  }

  info(message: string, context?: Record<string, unknown>): void {
    this.log('info', message, context);
  }

  warn(message: string, context?: Record<string, unknown>): void {
    this.log('warn', message, context);
  }

  error(message: string, context?: Record<string, unknown>): void {
    this.log('error', message, context);
  }
}

// Global logger instance
export const logger = new Logger();
