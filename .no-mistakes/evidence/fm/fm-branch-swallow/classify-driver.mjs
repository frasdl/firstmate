import { pathToFileURL } from "node:url";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const { activateEligibleRowsOwner, scopeForUnreadWake, writeEligibleRowsSnapshot, releaseEligibleRowsSnapshot, BRANCH_ELIGIBLE_ROWS_FILE } =
  await import(pathToFileURL(process.env.LIB).href);
const state = `${process.env.FM_HOME}/state`;
const project = `${process.env.FM_HOME}/projects/approved`;
mkdirSync(`${state}`, { recursive: true });
mkdirSync(`${project}`, { recursive: true });
writeFileSync(`${state}/task-a.meta`, `project=${project}\nwindow=fm-window\n`);

const show = (label, scope) => console.log(label, JSON.stringify({
  status: scope.status, eligible: scope.eligible, corrupted: scope.corrupted,
  eligibleSeqs: scope.eligibleSeqs, projects: scope.projects,
}));

// 1. Legible-but-unmapped signal row (task torn down while wake still queued).
writeFileSync(`${state}/.wake-queue`, "1\t1\tsignal\ttorn-down-task.status\tsignal: torn-down-task.status\n");
show("unmapped-only:", scopeForUnreadWake(state, false));

// 2. Mixed queue: unmapped errant row must not veto the two resolvable rows.
writeFileSync(`${state}/.wake-queue`,
  ["1\t1\tstale\torphan-window\tstale: orphan-window",
   "1\t2\tsignal\ttask-a.status\tsignal: task-a.status",
   "1\t3\tstale\tfm-window\tstale: fm-window"].join("\n"));
const mixed = scopeForUnreadWake(state, false);
show("mixed:", mixed);

// 3. Heartbeat all-or-nothing rule for unmapped rows.
show("heartbeat-with-unmapped:", scopeForUnreadWake(state, true));

// 4. Structural corruption still vetoes the whole scan (fail-closed).
writeFileSync(`${state}/.wake-queue`, "not-a-tabbed-line\n1\t2\tsignal\ttask-a.status\tsignal: task-a.status\n");
show("malformed-line:", scopeForUnreadWake(state, false));

// 5. Publish the eligible snapshot through the real grant bin.
writeFileSync(`${state}/.wake-queue`,
  ["1\t1\tstale\torphan-window\tstale: orphan-window",
   "1\t2\tsignal\ttask-a.status\tsignal: task-a.status",
   "1\t3\tstale\tfm-window\tstale: fm-window"].join("\n"));
const scope = scopeForUnreadWake(state, false);
if (!activateEligibleRowsOwner(state, process.env.GRANT, process.pid, "evidence-driver")) process.exit(2);
const pub = writeEligibleRowsSnapshot(state, scope.eligibleSeqs, process.env.GRANT, "evidence-driver");
const snapshot = readFileSync(`${state}/${BRANCH_ELIGIBLE_ROWS_FILE}`, "utf8").trim().split("\n");
console.log("snapshot-publish:", pub, "rows:", JSON.stringify(snapshot), "== [2,3]:", snapshot.join(",") === "2,3");
releaseEligibleRowsSnapshot(state, process.env.GRANT, "evidence-driver");
process.exit(0);
