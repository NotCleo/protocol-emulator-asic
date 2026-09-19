# Physical implementation results

## Status

No local IHP hardening result is available yet.

The official Tiny Tapeout support tools were cloned to `/tmp/tt-support-tools`.
The documented configuration command was attempted:

```text
python3 /tmp/tt-support-tools/tt_tool.py --project-dir . --create-user-config --ihp
```

It stopped before project configuration because the project-local virtual
environment did not contain `chevron`. Installing the official requirements
was then attempted, but the package index was unreachable. Docker is installed
but the current user cannot access its daemon socket. Consequently the
LibreLane/IHP hardening flow could not be started locally.

The repository's official workflow remains enabled in
`.github/workflows/gds.yaml` with `TinyTapeout/tt-gds-action@ttihp26b` and
`ihp-sg13g2`. No synthesis, placement, routing, timing, DRC, antenna, or
6x4-fit metrics are reported until that flow completes.

| Metric | Result |
|---|---|
| Synthesis cells | Not available |
| Sequential cells | Not available |
| Mapped area | Not available |
| IMEM implementation | Not available; RTL is an inferred register array |
| Placement utilization | Not available |
| Routing/congestion | Not available |
| WNS/TNS | Not available |
| Critical path/Fmax | Not available |
| 6x4 fit | Not determined |
