# CF-pushable Telegraf
This provides the Telegraf binary as a cf-pushable application and includes a Telegraf config generator sidecar.

The Telegraf config generator produces a Telegraf config with the Prometheus input plugin using metrics endpoints
published to NATs. This config gets regenerated every 15 seconds to keep up-to-date with all the metrics endpoints and
restarts Telegraf to read this new config.

## Minimum Requirements
* BOSH CLI v6.1.1
* CF CLI v6.47.0
* CF Deployment v12.21.0
* Credhub CLI version 2.5.3

## Usage
1. Add output plugin(s) to telegraf.conf
1. `cf`, `credhub`, and `bosh` target the desired environment
1. `./push.sh`

## Scaling
#### Min instances: 2
Due to application security groups, Telegraf cannot scrape the Diego Cell it is running on.
This means there must be at least 2 instances of Telegraf (on different diego cells) in
order to ingest all metrics.

#### Dropping metrics
This promQL query will allow you to determine if a specific output is not keeping up.
A good number to shoot for is 99% of metrics getting through.
Just replace `my-output-plugin` with the name of your output e.g. datadog.
```
100 * (1 -
  rate(internal_write_metrics_dropped{output="my-output-plugin"}[1m]) /
  rate(internal_write_metrics_written{output="my-output-plugin"}[1m]))
```

If this number is below 99%, try increasing the `metric_buffer_limit`.

#### Duplicate metrics
If telegraf is scaled to more than one instance, it will emit duplicate metrics.
