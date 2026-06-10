import Foundation

enum TypeScriptProjectScaffold {
  struct Options: Equatable, Sendable {
    var projectName: String

    init(projectName: String) {
      self.projectName = Self.packageName(projectName)
    }

    private static func packageName(_ raw: String) -> String {
      let normalized =
        raw
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
      return normalized.isEmpty ? "compass-typescript-app" : normalized
    }
  }

  struct ScaffoldFile: Equatable, Sendable {
    var path: String
    var contents: String
  }

  static func files(options: Options) -> [ScaffoldFile] {
    let name = options.projectName
    return [
      ScaffoldFile(path: "pnpm-workspace.yaml", contents: pnpmWorkspace),
      ScaffoldFile(path: ".gitignore", contents: gitignore),
      ScaffoldFile(path: "README.md", contents: readme(projectName: name)),
      ScaffoldFile(path: "package.json", contents: rootPackageJSON(projectName: name)),
      ScaffoldFile(path: "tsconfig.base.json", contents: tsconfigBase),
      ScaffoldFile(path: "packages/core/package.json", contents: corePackageJSON(projectName: name)),
      ScaffoldFile(path: "packages/core/tsconfig.json", contents: packageTSConfig),
      ScaffoldFile(path: "packages/core/src/index.ts", contents: coreIndex),
      ScaffoldFile(path: "packages/core/src/index.test.ts", contents: coreTest),
      ScaffoldFile(path: "packages/cli/package.json", contents: cliPackageJSON(projectName: name)),
      ScaffoldFile(path: "packages/cli/tsconfig.json", contents: packageTSConfig),
      ScaffoldFile(path: "packages/cli/src/main.ts", contents: cliMain(projectName: name)),
      ScaffoldFile(path: "packages/cli/src/main.test.ts", contents: cliTest(projectName: name)),
      ScaffoldFile(path: "packages/web/package.json", contents: webPackageJSON(projectName: name)),
      ScaffoldFile(path: "packages/web/tsconfig.json", contents: webTSConfig),
      ScaffoldFile(path: "packages/web/index.html", contents: webIndex(projectName: name)),
      ScaffoldFile(path: "packages/web/src/App.tsx", contents: webApp(projectName: name)),
      ScaffoldFile(path: "packages/web/src/App.test.tsx", contents: webAppTest),
      ScaffoldFile(path: "packages/web/src/main.tsx", contents: webMain),
      ScaffoldFile(path: "packages/web/src/styles.css", contents: webStyles),
    ]
  }

  static func write(to url: URL, options: Options) throws {
    let fm = FileManager.default
    for file in files(options: options) {
      let destination = url.appending(path: file.path)
      try fm.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
      )
      try file.contents.write(to: destination, atomically: true, encoding: .utf8)
    }
  }

  static func isGeneratedWorkspace(at url: URL) -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: url.appending(path: "pnpm-workspace.yaml").path)
      && fm.fileExists(atPath: url.appending(path: "packages/core/package.json").path)
      && fm.fileExists(atPath: url.appending(path: "packages/cli/package.json").path)
      && fm.fileExists(atPath: url.appending(path: "packages/web/package.json").path)
  }

  private static let pnpmWorkspace = """
    packages:
      - "packages/*"
    """

  private static let gitignore = """
    node_modules/
    dist/
    coverage/
    .DS_Store
    *.log
    """

  private static func readme(projectName: String) -> String {
    """
    # \(projectName)

    A Compass-generated TypeScript workspace.

    ## Commands

    - `pnpm verify`
    - `pnpm test -- --coverage`
    - `pnpm build`
    - `pnpm typecheck`
    """
  }

  private static func rootPackageJSON(projectName: String) -> String {
    """
    {
      "name": "\(projectName)",
      "version": "0.1.0",
      "private": true,
      "type": "module",
      "packageManager": "pnpm@9.15.4",
      "scripts": {
        "verify": "pnpm typecheck && pnpm test -- --coverage && pnpm build",
        "test": "vitest run",
        "build": "pnpm -r build",
        "typecheck": "pnpm -r typecheck"
      },
      "devDependencies": {
        "@types/node": "^22.10.5",
        "@vitest/coverage-v8": "^2.1.8",
        "typescript": "^5.7.3",
        "vitest": "^2.1.8"
      }
    }
    """
  }

  private static let tsconfigBase = """
    {
      "compilerOptions": {
        "target": "ES2022",
        "useDefineForClassFields": true,
        "lib": ["ES2022", "DOM", "DOM.Iterable"],
        "allowJs": false,
        "skipLibCheck": true,
        "esModuleInterop": true,
        "allowSyntheticDefaultImports": true,
        "strict": true,
        "forceConsistentCasingInFileNames": true,
        "module": "ESNext",
        "moduleResolution": "Bundler",
        "resolveJsonModule": true,
        "isolatedModules": true,
        "noEmit": true,
        "jsx": "react-jsx"
      }
    }
    """

  private static let packageTSConfig = """
    {
      "extends": "../../tsconfig.base.json",
      "include": ["src"]
    }
    """

  private static let webTSConfig = """
    {
      "extends": "../../tsconfig.base.json",
      "include": ["src", "index.html"],
      "compilerOptions": {
        "types": ["vitest/globals", "jsdom"]
      }
    }
    """

  private static func corePackageJSON(projectName: String) -> String {
    """
    {
      "name": "@\(projectName)/core",
      "version": "0.1.0",
      "type": "module",
      "exports": {
        ".": "./src/index.ts"
      },
      "scripts": {
        "build": "tsc -p tsconfig.json",
        "typecheck": "tsc -p tsconfig.json"
      }
    }
    """
  }

  private static let coreIndex = """
    export interface WorkItem {
      id: string;
      title: string;
      done: boolean;
    }

    export function summarizeQueue(items: readonly WorkItem[]): string {
      const open = items.filter((item) => !item.done).length;
      return `${open} open / ${items.length} total`;
    }
    """

  private static let coreTest = """
    import { describe, expect, it } from "vitest";
    import { summarizeQueue } from "./index";

    describe("summarizeQueue", () => {
      it("counts open items", () => {
        expect(
          summarizeQueue([
            { id: "one", title: "First", done: false },
            { id: "two", title: "Second", done: true }
          ])
        ).toBe("1 open / 2 total");
      });
    });
    """

  private static func cliPackageJSON(projectName: String) -> String {
    """
    {
      "name": "@\(projectName)/cli",
      "version": "0.1.0",
      "type": "module",
      "bin": {
        "\(projectName)": "./src/main.ts"
      },
      "scripts": {
        "dev": "tsx src/main.ts",
        "build": "tsc -p tsconfig.json",
        "typecheck": "tsc -p tsconfig.json"
      },
      "dependencies": {
        "@\(projectName)/core": "workspace:*"
      },
      "devDependencies": {
        "tsx": "^4.19.2"
      }
    }
    """
  }

  private static func cliMain(projectName: String) -> String {
    """
    #!/usr/bin/env tsx
    import { summarizeQueue } from "@\(projectName)/core";

    export function main(argv = process.argv.slice(2)): string {
      const title = argv.join(" ").trim() || "First Compass task";
      return summarizeQueue([{ id: "task-1", title, done: false }]);
    }

    if (import.meta.url === `file://${process.argv[1]}`) {
      console.log(main());
    }
    """
  }

  private static func cliTest(projectName: String) -> String {
    """
    import { describe, expect, it } from "vitest";
    import { main } from "./main";

    describe("@\(projectName)/cli", () => {
      it("prints the queue summary", () => {
        expect(main(["Ship", "it"])).toBe("1 open / 1 total");
      });
    });
    """
  }

  private static func webPackageJSON(projectName: String) -> String {
    """
    {
      "name": "@\(projectName)/web",
      "version": "0.1.0",
      "type": "module",
      "scripts": {
        "dev": "vite",
        "build": "vite build",
        "typecheck": "tsc -p tsconfig.json"
      },
      "dependencies": {
        "@\(projectName)/core": "workspace:*",
        "@vitejs/plugin-react": "^4.3.4",
        "vite": "^6.0.7",
        "react": "^19.0.0",
        "react-dom": "^19.0.0"
      },
      "devDependencies": {
        "@types/jsdom": "^21.1.7",
        "@types/react": "^19.0.4",
        "@types/react-dom": "^19.0.2",
        "jsdom": "^25.0.1"
      }
    }
    """
  }

  private static func webIndex(projectName: String) -> String {
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>\(projectName)</title>
      </head>
      <body>
        <div id="root"></div>
        <script type="module" src="/src/main.tsx"></script>
      </body>
    </html>
    """
  }

  private static func webApp(projectName: String) -> String {
    """
    import { summarizeQueue, type WorkItem } from "@\(projectName)/core";

    const seedItems: WorkItem[] = [
      { id: "brief", title: "Shape the brief", done: true },
      { id: "slice", title: "Ship the next slice", done: false }
    ];

    export function App() {
      return (
        <main>
          <p className="eyebrow">Compass workspace</p>
          <h1>\(projectName)</h1>
          <p>{summarizeQueue(seedItems)}</p>
        </main>
      );
    }
    """
  }

  private static let webAppTest = """
    import { describe, expect, it } from "vitest";
    import { App } from "./App";

    describe("App", () => {
      it("is importable", () => {
        expect(App).toBeTypeOf("function");
      });
    });
    """

  private static let webMain = """
    import React from "react";
    import { createRoot } from "react-dom/client";
    import { App } from "./App";
    import "./styles.css";

    createRoot(document.getElementById("root")!).render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    );
    """

  private static let webStyles = """
    :root {
      color: #171717;
      background: #f6f7f8;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    body {
      margin: 0;
    }

    main {
      min-height: 100vh;
      display: grid;
      place-content: center;
      gap: 12px;
      padding: 32px;
    }

    h1,
    p {
      margin: 0;
    }

    h1 {
      font-size: 40px;
      line-height: 1.1;
    }

    .eyebrow {
      color: #59636e;
      font-size: 13px;
      text-transform: uppercase;
    }
    """
}
