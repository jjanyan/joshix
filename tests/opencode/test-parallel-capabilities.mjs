import { pathToFileURL } from 'url';

const [, , pluginPath] = process.argv;

if (!pluginPath) {
  console.error('Usage: node test-parallel-capabilities.mjs PLUGIN_PATH');
  process.exit(2);
}

const mod = await import(pathToFileURL(pluginPath).href);
const plugin = await mod.JoshixPlugin({ client: {}, directory: '.' });
const transform = plugin['experimental.chat.messages.transform'];
const output = {
  messages: [{
    info: { role: 'user' },
    parts: [{ type: 'text', text: 'parallel capability test' }],
  }],
};

await transform({}, output);

const injectedText = output.messages
  .flatMap((message) => message.parts)
  .filter((part) => part.type === 'text')
  .map((part) => part.text)
  .join('\n');

const expectedStatements = [
  'Multiple independent subagents → parallel @mentions when supported; otherwise serial execution',
  'Unknown capacity → start with at most two workers',
  'Completion without individual observation → bounded join-all waves',
  'Same-worker continuation unavailable → fully briefed replacement worker',
  'Interactive questions → return NEEDS_CONTEXT to the lead',
  'Reasoning controls unavailable → inherit the OpenCode default without claiming a specific effort',
];

const missing = expectedStatements.filter(
  (statement) => !injectedText.includes(statement)
);

if (missing.length > 0) {
  for (const statement of missing) {
    console.error(`FAIL: missing injected statement: ${statement}`);
  }
  process.exit(1);
}

console.log('All parallel capability statements were injected.');
