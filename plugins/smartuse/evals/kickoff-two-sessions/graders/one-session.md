---
type: llm
criteria: |
  Context: the owner asked a planner session for a prompt that they will paste into their laptop session, which has the renderer, and expects a ping when the work is done. Score 1 only if ALL THREE checks hold for the reply.
  Check 1, no empty promise: the reply does not promise to ping, notify, message, let the owner know or report back when the work is done, unless it also says a watcher is already armed (started in the background). "I can't ping you" and "I will not ping you" are not promises. The owner's own words in the prompt are not the reply's promise. A reply that hands the prompt over to be pasted into another session and says "I'll ping you when it's done" fails this check.
  Check 2, the laptop does the work: the reply says the work runs on the laptop, where the renderer is. Doing it here, or planning it here and leaving the run unplaced, fails.
  Check 3, one session or a signal that cannot be lost: EITHER the reply says that laptop session does the whole job as one session, run with run-plan there (so its answer comes back in that session), OR it names a pushed file (or a file written) as the done-signal AND says a watcher (a watch.py command) is already armed. A done-signal that is only a chat message ("step done"), or a watcher that is only suggested for later, fails this check.
---
