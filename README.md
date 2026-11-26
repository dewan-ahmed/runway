# runway

Vendor-neutral usage forecasting and budget guard CLI for agent workflows.

`runway` reads usage data that software factories officially expose, forecasts
consumption through the end of a budget period, and returns an exit code an
agent or CI job can act on.

It does not scrape dashboards or call private APIs.

## Supported inputs

- Devin daily consumption API responses.
- Factory Analytics `/tokens` responses.
- Cosmos OpenTelemetry trace exports using `cosmos.credits` or
  `cosmos.cost_usd`.

Save the official API response or OTLP JSON payload to a file before running
`runway`. Direct API calls and credential handling are intentionally outside
the MVP.

## Build

Install the V version in `.v-version`, then run:

```sh
v -prod -o runway .
```

## Use

```sh
runway check \
  --source devin \
  --file consumption.json \
  --budget 1000 \
  --period-start 2026-11-01 \
  --period-end 2026-11-30 \
  --warn-at 80 \
  --stop-at 100
```

For Cosmos traces, choose credits or US dollars:

```sh
runway check \
  --source cosmos \
  --measure credits \
  --file traces.json \
  --budget 10000 \
  --period-start 2026-11-01 \
  --period-end 2026-11-30
```

The latest date in the input is the default `--as-of` date. Pass `--as-of`
to make forecasts reproducible when an export contains future or incomplete
records.

## Output

The command emits one JSON document with:

- Usage and remaining budget.
- Average daily burn rate.
- Forecast usage and utilization at period end.
- Estimated exhaustion date when it falls inside the period.
- `ok`, `warning`, or `stop` status.

Thresholds apply to forecast utilization, so a rapidly growing workload can
be stopped before the current balance is exhausted.

## Anomalies

```sh
runway anomalies --source devin --file consumption.json [--as-of DATE] \
  [--lookback 28] [--threshold 3.5]
```

Budget thresholds catch a runaway agent only after the spend has added up.
`anomalies` compares the `--as-of` day (default: latest date in the input)
with the same day type, weekday or weekend, over the previous `--lookback`
days. It uses a median/MAD robust z-score, so the result is deterministic
and easy to explain. Days missing from the window count as zero.

The JSON report includes `baseline_days`, `median`, `mad`, `value`, `score`,
`status`, and `reason_code`:

| Status | Reason code | Exit code |
| --- | --- | --- |
| `ok` | empty | `0` |
| `anomaly` | `BURN_RATE_SPIKE` | `4` |
| `insufficient_baseline` | `INSUFFICIENT_BASELINE` | `0` |

The baseline is insufficient when the input does not cover the full lookback
window, so the command reports that instead of guessing. Exit code `4` is
kept separate from the budget exit codes so callers can branch on it.

## Official data references

- [Devin daily consumption API](https://docs.devin.ai/api-reference/v3/consumption/organizations-consumption-daily)
- [Factory Analytics API](https://docs.factory.com/api-reference/analytics)
- [Cosmos Trace Export](https://docs.augmentcode.com/cosmos/trace-export/reference)

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Forecast is below the warning threshold. |
| `1` | Forecast reached the warning threshold. |
| `2` | Forecast reached the stop threshold. |
| `3` | Arguments or input data were invalid. |

## License

MIT
