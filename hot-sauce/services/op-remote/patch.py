"""Patch op-remote's bundled dist/cli.js. Usage: python3 patch.py <in.js> <out.js>

Upstream op-remote resolves every secret in its .env.tpl once, at startup, and keeps
the values in its environment. Hermes is general-purpose, so that list would be
everything. This patch makes it:

1. Lazy: at startup it stores only name -> op:// reference. After Tanvi approves a
   request in Telegram, it runs `op read` for just the requested references.
2. Keep the 1Password CLI session alive (`op whoami` every 10 minutes), because a
   CLI session expires after 30 minutes idle and reads now happen later.
3. Drop the Auto-Approve button: one tap would approve every later request.
4. Put its socket in $OP_REMOTE_SOCK_DIR with mode 0660, so Hermes (another macOS
   user, in the socket's group) can connect to an op-remote running as _opremote.

Every anchor must match exactly the expected number of times, so an upstream change
fails loudly instead of half-patching.
"""
import sys

HELPERS = r'''
var __refs = new Map;
var __labels = new Map;
var __texts = new Map;
function __esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
async function __readRefs(envFile) {
  const { secretVars } = await readEnvFile(envFile);
  const refs = new Map, labels = new Map;
  for (const v of secretVars)
    refs.set(v.name, v.ref);
  // "#: NAME<TAB>alt.inc › Item › field" lines from gen-secrets.py: readable labels.
  for (const line of (await Bun.file(envFile).text()).split("\n")) {
    const m = line.match(/^#: (\S+)\t(.+)$/);
    if (m)
      labels.set(m[1], m[2]);
  }
  __refs = refs;
  __labels = labels;
}
async function __loadRefs(envFile) {
  await __readRefs(envFile);
  // keepalive.sh rebuilds the list hourly; pick up new items without a restart.
  setInterval(() => {
    __readRefs(envFile).catch((e) => console.error("[op-remote] list reload failed:", e));
  }, 5 * 60 * 1000);
  setInterval(() => {
    Bun.spawn(["op", "whoami"], { stdout: "ignore", stderr: "ignore" });
  }, 10 * 60 * 1000);
}
async function __fetchApproved(refs) {
  const env = {};
  for (const [name, ref] of Object.entries(refs)) {
    const proc = Bun.spawn(["op", "read", "--no-newline", ref], { stdout: "pipe", stderr: "pipe" });
    const value = await new Response(proc.stdout).text();
    const err = await new Response(proc.stderr).text();
    if (await proc.exited !== 0) {
      console.error(`[op-remote] op read failed for ${name}: ${err.trim()}`);
      return { status: "rejected", reason: `1Password read failed for ${name}. The server may need signing in again.` };
    }
    env[name] = value;
  }
  return { status: "approved", env };
}
async function startServer('''

# Message formatting. Upstream sends plain text led by the raw command, and on a tap
# replaces the whole message with "Approved at 00:12", so the chat no longer shows what
# was approved. Patched: HTML, reason first, readable secret labels, command in a
# code block, and the status appended under the original request. Every value Hermes
# controls (reason, command, cwd) is HTML-escaped so it can't fake formatting.
OLD_TEXT = r'''  const secretList = opts.secretNames.map((s) => `  - ${s}`).join(`
`);
  const text = [
    "\uD83D\uDD11 Secret access request",
    "",
    `Reason: ${opts.reason}`,
    "",
    `Command: ${opts.command.join(" ")}`,
    `Working dir: ${opts.cwd}`,
    "Secrets:",
    secretList
  ].join(`
`);
'''
NEW_TEXT = r'''  const __cmd = opts.command.join(" ");
  const __cmdShown = __cmd.length > 700 ? `${__cmd.slice(0, 700)} … (${__cmd.length - 700} more characters)` : __cmd;
  const secretList = opts.secretNames.map((s) => `• ${__esc(__labels.get(s) ?? s)}`).join("\n");
  const text = [
    "\u{1F511} <b>Hermes wants a secret</b>",
    "",
    `<b>Why:</b> ${__esc(opts.reason)}`,
    "",
    "<b>Secrets:</b>",
    secretList,
    "",
    "<b>Will run:</b>",
    `<pre>${__esc(__cmdShown)}</pre>`,
    `<i>in ${__esc(opts.cwd)}</i>`
  ].join("\n");
'''
OLD_SEND = '''    text,
    reply_markup: keyboard
  });
  return awaitApproval(config2, sent.message_id, nonce);
}
async function requestResumeApproval('''
NEW_SEND = '''    text,
    parse_mode: "HTML",
    reply_markup: keyboard
  });
  __texts.set(sent.message_id, text);
  return awaitApproval(config2, sent.message_id, nonce);
}
async function requestResumeApproval('''
OLD_BUTTONS = '''      { text: "Approve", callbackData: "approve" },
      { text: "Reject", callbackData: "reject" }
    ],
    [
      { text: "Stop", callbackData: "stop" }
    ]'''
NEW_BUTTONS = '''      { text: "\\u2705 Approve", callbackData: "approve" },
      { text: "\\u274C Reject", callbackData: "reject" }
    ],
    [
      { text: "\\u26D4 Stop all requests", callbackData: "stop" }
    ]'''
OLD_EDIT = '''    message_id: messageId,
    text
  }), context);'''
NEW_EDIT = '''    message_id: messageId,
    ...__texts.has(messageId) ? { text: `${__texts.get(messageId)}\\n\\n<b>${__esc(text)}</b>`, parse_mode: "HTML" } : { text }
  }), context);'''

EDITS = [
    # (old, new, expected count)
    ("    await loadEnvFile(opts.envFile);\n", "    await __loadRefs(opts.envFile);\n", 1),
    ("          const value = process.env[name];\n", "          const value = __refs.get(name);\n", 1),
    ('return { status: "approved", env: resolved.env };', "return await __fetchApproved(resolved.env);", 3),
    ("      if (autoApprove) {\n", "      if (false) {\n", 1),
    ('      { text: "Auto-Approve", callbackData: "auto_approve" },\n', "", 1),
    ('  const dir = `${process.env.TMPDIR ?? "/tmp"}/op-remote`;\n',
     '  const dir = process.env.OP_REMOTE_SOCK_DIR ?? `${process.env.TMPDIR ?? "/tmp"}/op-remote`;\n', 1),
    ("    chmodSync(sockPath, 384);\n",
     "    chmodSync(sockPath, process.env.OP_REMOTE_SOCK_DIR ? 432 : 384);\n", 1),
    (OLD_TEXT, NEW_TEXT, 1),
    (OLD_SEND, NEW_SEND, 1),
    (OLD_BUTTONS, NEW_BUTTONS, 1),
    (OLD_EDIT, NEW_EDIT, 1),
    ("\nasync function startServer(", "\n" + HELPERS.lstrip("\n"), 1),
]

src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
for old, new, n in EDITS:
    found = s.count(old)
    if found != n:
        sys.exit(f"patch.py: expected {n} of {old.strip()[:60]!r}, found {found}. Upstream changed; update the patch.")
    s = s.replace(old, new)
open(dst, "w").write(s)
print(f"patched {src} -> {dst}")
