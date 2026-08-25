# Primary delegation-shape guard verification

Audience: maintainer verification.

Active version-scoped evidence that the primary-session delegation-shape guard is wired and enforced per harness.
`docs/subagent-guard.md` owns the contract, the tool-shape classifier, the per-harness applicability review, and the deny-message routing.
This record keeps only the empirical facts that refresh each harness row.

## Pi / pi-signed, 2026-08-25

Verified on 2026-08-25 against Pi 0.84.3 with pi-subagents 0.56.0 installed, provider `opencode-go/gpt-5.6-luna`, on Linux (kernel 7.1.5-arch1-2).

The lab was a throwaway git-initialized firstmate-shaped project under the task worktree, containing `AGENTS.md`, `state/`, a `bin/` copy of the guard script and its scope and seatbelt dependencies, and a copy of the modified `.pi/extensions/fm-primary-turnend-guard.ts` plus a throwaway probe extension that logs every `tool_call`'s `toolName`, and a throwaway extension registering a delegation-shaped scratch tool named `spawn_worker` whose `execute` writes a sentinel file.
No modified file was installed into the primary checkout.
No live watcher, fleet state, or herdr lifecycle command was used.

The launch command for every run was, from the scratch project root:

```sh
pi -p --no-session --no-context-files --no-extensions --no-skills \
  -e .pi/extensions/fm-tool-probe.ts \
  -e .pi/extensions/fm-scratch-delegation-tool.ts \
  -e .pi/extensions/fm-primary-turnend-guard.ts \
  --thinking low "$PROMPT"
```

The pi-subagents run added `-e /home/francesco/.pi/agent/npm/node_modules/pi-subagents/index.ts`.

| Run | Prompt | Result |
| --- | --- | --- |
| A | `Use the read tool to read the file AGENTS.md in the current directory, then reply with READ_LINE=<its first line>` | Model replied `READ_LINE=# primary fixture`. Probe log recorded `{"toolName":"read",...}`. The ordinary non-bash tool reached the handler and executed. |
| B | `Call the spawn_worker tool with action list. You MUST actually attempt the spawn_worker tool call. Report exactly what happened, including any block reason text you received.` | Model reported the call was denied with `[subagent-dispatch] ... (blocked tool: spawn_worker, delegation-shaped on "spawn")`. The sentinel file stayed absent, so the tool never executed. |
| C | `List the exact names of every tool available to you in this session, one per line, nothing else. Then call the subagent tool with action list - you MUST actually attempt the subagent tool call. Report the block reason text you receive.` | Tool listing: `read`, `bash`, `edit`, `write`, `subagent`, `subagent_wait`, `subagent_supervisor`. The `subagent` call was blocked with `[subagent-dispatch] ... (blocked tool: subagent, delegation-shaped on "agent")`. Probe log recorded `{"toolName":"subagent",...}`. |
| D | Same prompt as B, launched with `FM_ALLOW_SUBAGENT=1` | `spawn_worker` executed; the sentinel file was written (`EXECUTED`). The escape hatch works end to end. |
| E | Same prompt as B, run inside a linked git worktree of the lab project | `spawn_worker` executed; the sentinel file was written. The guard is inert in a crewmate-shaped linked worktree. |

Observed deny reason text for the blocked `subagent` call, as reported by the model:

```text
[subagent-dispatch] the firstmate primary dispatches through the fleet, not the harness's own delegation tools: work started that way has no durable fleet record, leaves every firstmate guard inert, and dies with this session. Instead, first classify the work under the AGENTS.md intake contract, then use bin/fm-brief.sh followed by bin/fm-spawn.sh for dispatched work (blocked tool: subagent, delegation-shaped on "agent"). Launch the session with FM_ALLOW_SUBAGENT=1 for a deliberate exception.
```

The block is executed by Pi's extension engine before tool execution: run B's sentinel never appeared while runs D and E wrote it, and the probe log in the probe-first ordering recorded `spawn_worker` and `subagent` before the guard's deny, which proves the non-bash `tool_call` reaches the handler with a real tool name, including pi-subagents' actual `subagent` tool.

Refresh with the same procedure after any Pi or pi-subagents upgrade, following the `firstmate-coding-guidelines` live-guard rule.
