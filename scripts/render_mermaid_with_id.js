#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { randomUUID } = require('crypto');

(async () => {
  try {
    const repoRoot = path.resolve(__dirname, '..');
    const inFile = path.join(repoRoot, 'docs', 'system_flowchart.mmd');
    const outFile = path.join(repoRoot, 'docs', 'system_flowchart_with_id.mmd');
    const outPng = path.join(repoRoot, 'docs', 'system_flowchart_with_id.png');

    if (!fs.existsSync(inFile)) {
      console.error('Input Mermaid file not found:', inFile);
      process.exit(2);
    }

    const raw = fs.readFileSync(inFile, 'utf8');
    const id = randomUUID();

    // Create header comment with system id
    const header = `%% SYSTEM_ID: ${id}\n%% Inserted by scripts/render_mermaid_with_id.js\n`;

    // Insert a small system node after the `flowchart LR` declaration so it appears on canvas
    const flowKey = 'flowchart LR';
    let newContent;
    const flowIndex = raw.indexOf(flowKey);
    if (flowIndex === -1) {
      newContent = header + raw;
    } else {
      // find end of the `flowchart LR` line
      const lineEnd = raw.indexOf('\n', flowIndex);
      const insertPos = lineEnd >= 0 ? lineEnd + 1 : flowIndex + flowKey.length;
      const sysNode = `SYS[POS System\\nID: ${id}]\nSYS --> A1\n\n`;
      newContent = raw.slice(0, insertPos) + sysNode + raw.slice(insertPos);
      newContent = header + newContent;
    }

    fs.writeFileSync(outFile, newContent, 'utf8');
    console.log('Wrote file:', outFile);
    console.log('Generated SYSTEM ID:', id);

    // Try to render using npx mermaid-cli (works even if not globally installed)
    const cmd = `npx --yes @mermaid-js/mermaid-cli -i "${outFile}" -o "${outPng}" -w 1600`;
    console.log('Rendering to PNG via:', cmd);

    exec(cmd, { cwd: repoRoot, maxBuffer: 1024 * 1024 * 5 }, (err, stdout, stderr) => {
      if (stdout && stdout.trim()) console.log(stdout);
      if (stderr && stderr.trim()) console.error(stderr);
      if (err) {
        console.error('Render failed (you can run the command manually):', err.message);
        console.log('\nIf rendering fails, try:');
        console.log(`npx @mermaid-js/mermaid-cli -i "${outFile}" -o "${outPng}" -w 1600`);
        process.exitCode = 0; // not a fatal error for script
        return;
      }

      console.log('Rendered PNG saved to:', outPng);
    });
  } catch (e) {
    console.error('Unexpected error:', e);
    process.exit(1);
  }
})();
