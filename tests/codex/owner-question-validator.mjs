import fs from 'node:fs';

// Validate emitted Markdown, not the fenced source example in the reference.
const lines = fs.readFileSync(0, 'utf8').trimEnd().split('\n');
const mode = process.argv[2] ?? 'full';
const questions = [];
let fence;
lines.forEach((line, i) => {
  const marker = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
  if (marker) {
    if (!fence) fence = marker[1];
    else if (marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) fence = undefined;
    return;
  }
  if (!fence && /^## .+\?$/.test(line)) questions.push(i);
});
const check = (condition, message) => { if (!condition) throw new Error(message); };
try {
  check(questions.length === 1, 'expected one H2 question');
  const start = questions[0];
  const body = lines.slice(start);
  check(!body.slice(1).some(line => line.includes('?')), 'expected only one question in the owner lane');
  if (mode === 'single') process.exit(0);
  check(start === 0 || lines[start - 1] === '', 'blank line before question');
  check(lines[start + 1] === '', 'blank line after question');
  check(!body.some(line => /^\s*(```|~~~)/.test(line)), 'question must render, not be fenced');
  const choices = body.flatMap((line, i) => /^### Choice [A-Z]: .+/.test(line) ? [i] : []);
  check(choices.length >= 2 && choices.length <= 4, 'expected two to four choices');
  check(choices.every((position, index) => body[position].startsWith(`### Choice ${'ABCD'[index]}: `)),
    'choices must be sequential A–D');
  check(choices.filter(position => body[position].endsWith(' — Recommended')).length === 1,
    'expected exactly one recommendation');
  if (mode === 'options') process.exit(0);
  const summaryLines = body.slice(2, choices[0]);
  check(summaryLines.at(-1) === '', 'blank line before first choice');
  const summary = summaryLines.join(' ').trim();
  check(summary.length > 0 && summary.split(/\s+/).length <= 100, 'summary must contain 1–100 words');
  check(!summaryLines.some(line => /^#|^(Example|History):/.test(line)), 'summary uses plain prose');
  choices.forEach((position, index) => {
    const block = body.slice(position + 1, choices[index + 1] ?? body.length);
    check(block[0] === '', 'blank line after choice heading');
    check(/^\*\*Pro\*\*: \S.* {2,}$/.test(block[1] ?? ''), 'Pro line needs its own hard break');
    check(/^\*\*Con\*\*: \S/.test(block[2] ?? ''), 'Con line must follow Pro');
    check(block.slice(3).every(line => line === ''), 'unexpected fields after choice');
    if (index < choices.length - 1) check(block.length >= 4, 'blank line between choices');
  });
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
