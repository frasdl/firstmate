# Test-phase live verification: Pi delegation-shape guard (fm/subagent-guard-pi)

Dated: 2026-08-26 (test phase of no-mistakes run on commit dce34114e6db7d2a56edcf26e55103b18cd9c1a6).
Environment: Pi 0.84.3, pi-subagents 0.56.0, provider opencode-go/gpt-5.6-luna, Linux.
The portable regression `tests/fm-subagent-pretool-check.test.sh` passes end to end (14 ok, exit 0),
including the new `test_pi_primary_tool_surface_is_guarded` which asserts through the public
`--tool` interface that `subagent subagent_wait subagent_supervisor` are denied and the Pi
primary's ordinary non-bash tools pass.

Live harness runs were executed in a throwaway firstmate-shaped scratch project
(`/tmp/fm-pi-guard-lab2`, git-initialized plain checkout with AGENTS.md, state/, bin/ copies of
the guard + scope + seatbelt scripts, `.pi/extensions/` copies of fm-primary-turnend-guard.ts and
lib/fm-operational-input.ts, plus a throwaway tool_call probe extension and a throwaway
delegation-shaped scratch tool `spawn_worker` whose execute writes a sentinel file). No modified
file was installed into the real firstmate checkout. Launch form for every run:

```sh
pi -p --no-session --no-context-files --no-extensions --no-skills \
  -e .pi/extensions/fm-tool-probe.ts \
  -e .pi/extensions/fm-scratch-delegation-tool.ts \
  [-e /home/francesco/.pi/agent/npm/node_modules/pi-subagents/index.ts] \
  -e .pi/extensions/fm-primary-turnend-guard.ts \
  --thinking low "$PROMPT"
```

| Run | What was exercised | Result |
| --- | --- | --- |
| A | Ordinary non-bash tool (`read AGENTS.md`) | Passed. Probe logged `{"toolName":"read"}`; model replied `READ_LINE=# primary fixture`. |
| B | Delegation-shaped scratch tool `spawn_worker` | Blocked at the tool surface. Model relayed `[subagent-dispatch] ... (blocked tool: spawn_worker, delegation-shaped on "spawn")` naming `bin/fm-brief.sh` then `bin/fm-spawn.sh`. Sentinel side effect never ran. Probe logged `{"toolName":"spawn_worker"}`. |
| C | Real pi-subagents `subagent` tool (pi-subagents index.ts loaded) | Blocked. Model relayed `[subagent-dispatch] ... (blocked tool: subagent, delegation-shaped on "agent")`. Probe logged `{"toolName":"subagent"}`. |
| D | Escape hatch `FM_ALLOW_SUBAGENT=1` with `spawn_worker` | Tool executed; sentinel file written `EXECUTED action=spawn worker=probe`. |
| E | Same wiring in a linked crewmate-shaped worktree of the lab repo | Guard inert: `spawn_worker` executed, sentinel written. |
| F | Bash through the modified handler | `printf BASH_LIVE_OK` executed; probe logged `{"toolName":"bash"}`. |
| G | Unchanged bash seatbelt chain through the handler (cd-guard live in lab) | `cd projects/foo` blocked at PreToolUse with `[persistent-cd]` deny JSON; watcher-arm/cd suites `tests/fm-cd-pretool-check.test.sh` and `tests/fm-arm-pretool-check.test.sh` also pass unchanged. |

Blocked-run deny reason (run C, verbatim from the model):
`[subagent-dispatch] the firstmate primary dispatches through the fleet, not the harness's own delegation tools: work started that way has no durable fleet record, leaves every firstmate guard inert, and dies with this session. Instead, first classify the work under the AGENTS.md intake contract, then use bin/fm-brief.sh followed by bin/fm-spawn.sh for dispatched work (blocked tool: subagent, delegation-shaped on "agent"). Launch the session with FM_ALLOW_SUBAGENT=1 for a deliberate exception.`

Probe logs (all runs, in handler registration order with the probe extension first):
see `probe-a.log` through `probe-g.log` under /tmp/fm-pi-guard-lab2 (throwaway and removed after the run).

Conclusion: the change satisfies the acceptance criteria — delegation-shaped non-bash tools on the
Pi primary are denied at the tool surface with the deny message routed to the fleet dispatch path
(both the scratch `spawn_worker` and pi-subagents' real `subagent`), ordinary non-bash tools pass,
the escape hatch and linked-worktree inertness behave as documented, and the existing bash
seatbelt behavior is unchanged.