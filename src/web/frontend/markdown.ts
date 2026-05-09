// Minimal markdown -> DOM renderer. Builds nodes with createElement /
// textContent only, so untrusted agent output cannot inject HTML.
//
// Supported: ATX headings, paragraphs, fenced code blocks, unordered and
// ordered lists, blockquotes, horizontal rules, inline code, bold (**),
// italic (*), and links. Anything unrecognized falls through as text.

export function renderMarkdown(source: string): DocumentFragment {
  const frag = document.createDocumentFragment();
  const lines = source.replace(/\r\n?/g, "\n").split("\n");
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    const fence = line.match(/^```(\w*)\s*$/);
    if (fence) {
      const buf: string[] = [];
      i++;
      while (i < lines.length && !/^```\s*$/.test(lines[i])) {
        buf.push(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      const pre = document.createElement("pre");
      pre.className = "md-code-block";
      const code = document.createElement("code");
      if (fence[1]) code.dataset.lang = fence[1];
      code.textContent = buf.join("\n");
      pre.appendChild(code);
      frag.appendChild(pre);
      continue;
    }

    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      const level = heading[1].length;
      const h = document.createElement(`h${level}`);
      h.className = `md-h${level}`;
      appendInline(h, heading[2]);
      frag.appendChild(h);
      i++;
      continue;
    }

    if (/^\s*([-*_])\s*\1\s*\1[-*_\s]*$/.test(line) && line.trim().length >= 3) {
      frag.appendChild(document.createElement("hr"));
      i++;
      continue;
    }

    if (line.trim() === "") {
      i++;
      continue;
    }

    if (/^\s*[-*]\s+/.test(line)) {
      const ul = document.createElement("ul");
      ul.className = "md-list";
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        const li = document.createElement("li");
        appendInline(li, lines[i].replace(/^\s*[-*]\s+/, ""));
        ul.appendChild(li);
        i++;
      }
      frag.appendChild(ul);
      continue;
    }

    if (/^\s*\d+\.\s+/.test(line)) {
      const ol = document.createElement("ol");
      ol.className = "md-list";
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        const li = document.createElement("li");
        appendInline(li, lines[i].replace(/^\s*\d+\.\s+/, ""));
        ol.appendChild(li);
        i++;
      }
      frag.appendChild(ol);
      continue;
    }

    if (/^>\s?/.test(line)) {
      const buf: string[] = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        buf.push(lines[i].replace(/^>\s?/, ""));
        i++;
      }
      const bq = document.createElement("blockquote");
      bq.className = "md-blockquote";
      appendInline(bq, buf.join(" "));
      frag.appendChild(bq);
      continue;
    }

    const buf: string[] = [];
    while (
      i < lines.length &&
      lines[i].trim() !== "" &&
      !/^(#{1,6}\s|```|\s*[-*]\s+|\s*\d+\.\s+|>\s?)/.test(lines[i])
    ) {
      buf.push(lines[i]);
      i++;
    }
    const p = document.createElement("p");
    p.className = "md-p";
    appendInline(p, buf.join(" "));
    frag.appendChild(p);
  }

  return frag;
}

function appendInline(parent: Node, source: string): void {
  let i = 0;
  while (i < source.length) {
    const rest = source.slice(i);

    let m = rest.match(/^`([^`\n]+)`/);
    if (m) {
      const code = document.createElement("code");
      code.className = "md-inline-code";
      code.textContent = m[1];
      parent.appendChild(code);
      i += m[0].length;
      continue;
    }

    m = rest.match(/^\*\*([^*\n]+)\*\*/) ?? rest.match(/^__([^_\n]+)__/);
    if (m) {
      const strong = document.createElement("strong");
      appendInline(strong, m[1]);
      parent.appendChild(strong);
      i += m[0].length;
      continue;
    }

    m = rest.match(/^\*([^*\n]+)\*/);
    if (m) {
      const em = document.createElement("em");
      appendInline(em, m[1]);
      parent.appendChild(em);
      i += m[0].length;
      continue;
    }

    m = rest.match(/^\[([^\]\n]+)\]\(([^)\s]+)\)/);
    if (m) {
      const a = document.createElement("a");
      a.href = m[2];
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      appendInline(a, m[1]);
      parent.appendChild(a);
      i += m[0].length;
      continue;
    }

    const next = rest.slice(1).search(/[`*\[]/);
    const end = next === -1 ? source.length : i + 1 + next;
    parent.appendChild(document.createTextNode(source.slice(i, end)));
    i = end;
  }
}
