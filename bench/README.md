# smartuse benchmark

Runs `/smartuse:make-prompt quick dry <ask>` on 5 typical asks against a tiny sample repo and prints one comparison table.

## Run

```bash
cd smartuse/bench
./run.sh                          # loads ../plugins/smartuse via --plugin-dir
./run.sh --plugin-dir /path/to/smartuse
```

Needs `claude` and `jq`. Each ask runs on a fresh temp copy of `sample-repo/` (git-initialised), so the fixture stays clean. Raw JSON goes to `results/<n>.json`. Runs spend plan usage (cap: 60 turns, $4 each).

## Table columns

- Cost: `total_cost_usd` for the run.
- Turns: `num_turns`, model round trips.
- Minutes: `duration_ms` / 60000.
- Prompt saved: result text contains "Prompt saved".
- Self-check: result text contains a "✓" line.

`sample-repo/` has one planted rabbit hole: `computeTotal()` in `orders.js` rounds silently (see its TODO). Good runs notice it without wandering off.

Numbers depend on your plan's models and on Claude Code's version; publish the version with the table.
