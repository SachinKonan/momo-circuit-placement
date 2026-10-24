# momo_proxy: clean-room CPU proxy evaluator

Incremental `Evaluator` for placement candidates (`score`, `apply`, `commit`, `revert`, `rebuild`,
`evaluate`, `evaluate_batch`, `evaluate_moves`), the interface the MOMO search program expects.

`proxy.c` is written only from the official Python scorer
(`external/MacroPlacement/CodeElements/Plc_client/plc_client_os.py`, with the grid-cell clamp from
`macro_place/objective.py`). It does not derive from any challenge entry.

Moving one block updates only that block's nets and grid cells: HPWL per net, the net's routing
(2-pin, 3-pin L/T, star split for larger nets) applied directly to the smoothed V/H arrays (smoothing
is linear), density area, and hard-macro routing allocation. Each score recomputes the density top 10%
and congestion top 5% with a linear-time selection. It scores in float32 geometry like the official
scorer; on our checks it matches the official proxy cost to about 1e-6. Every reported score in this
repository comes from the official evaluator, not from this library.

```sh
python submissions/momo/momo_proxy/build.py   # compiles libmomoproxy.so (setup.sh and the Dockerfile do this)
```
