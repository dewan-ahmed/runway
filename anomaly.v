module main

import math

const min_baseline_days = 7

struct AnomalyOptions {
	source    string
	file      string
	measure   string = 'credits'
	as_of     string
	lookback  int = 28
	threshold f64 = 3.5
}

struct AnomalyReport {
	version       int = 1
	source        string
	unit          string
	as_of         string
	day_type      string
	baseline_days int
	median        f64
	mad           f64
	value         f64
	score         f64
	status        string
	reason_code   string
}

fn parse_anomaly_options(args []string) !AnomalyOptions {
	mut values := map[string]string{}
	mut index := 0
	for index < args.len {
		flag := args[index]
		if flag !in ['--source', '--file', '--measure', '--as-of', '--lookback', '--threshold'] {
			return error('unknown option "${flag}"')
		}
		if index + 1 >= args.len {
			return error('${flag} requires a value')
		}
		values[flag] = args[index + 1]
		index += 2
	}
	if values['--source'] == '' || values['--file'] == '' {
		return error('anomalies requires --source and --file')
	}
	options := AnomalyOptions{
		source:    values['--source']
		file:      values['--file']
		measure:   values['--measure'] or { 'credits' }
		as_of:     values['--as-of'] or { '' }
		lookback:  (values['--lookback'] or { '28' }).int()
		threshold: (values['--threshold'] or { '3.5' }).f64()
	}
	if options.lookback < min_baseline_days {
		return error('--lookback must be at least ${min_baseline_days}')
	}
	if options.threshold <= 0 {
		return error('--threshold must be greater than zero')
	}
	return options
}

// detect_burn_spike compares the as-of day with the same day type (weekday or
// weekend) over the lookback window using a median/MAD robust z-score.
// Missing days in the window count as zero usage.
fn detect_burn_spike(series UsageSeries, options AnomalyOptions) !AnomalyReport {
	as_of_value := if options.as_of != '' { options.as_of } else { latest_date(series.days)! }
	as_of := parse_date(as_of_value)!
	mut by_date := map[string]f64{}
	for day in series.days {
		by_date[day.date] += day.amount
	}
	weekend := as_of.day_of_week() >= 6
	mut baseline := []f64{}
	for offset in 1 .. options.lookback + 1 {
		day := as_of.add_days(-offset)
		if (day.day_of_week() >= 6) == weekend {
			baseline << by_date[day.ymmdd()] or { 0.0 }
		}
	}
	value := by_date[as_of_value] or { 0.0 }
	mut report := AnomalyReport{
		source:        series.source
		unit:          series.unit
		as_of:         as_of_value
		day_type:      if weekend { 'weekend' } else { 'weekday' }
		baseline_days: baseline.len
		value:         round2(value)
		status:        'ok'
	}
	earliest := earliest_date(series.days)
	if baseline.len < min_baseline_days / 2 || earliest > as_of.add_days(-options.lookback).ymmdd() {
		return AnomalyReport{
			...report
			status:      'insufficient_baseline'
			reason_code: 'INSUFFICIENT_BASELINE'
		}
	}
	median := median_of(baseline)
	mad := median_of(baseline.map(math.abs(it - median)))
	// A flat baseline has MAD 0; fall back to 10% of the median (or 1 unit).
	scale := if mad > 0 { mad / 0.6745 } else { math.max(median * 0.1, 1.0) }
	score := (value - median) / scale
	report = AnomalyReport{
		...report
		median: round2(median)
		mad:    round2(mad)
		score:  round2(score)
	}
	if score >= options.threshold {
		return AnomalyReport{
			...report
			status:      'anomaly'
			reason_code: 'BURN_RATE_SPIKE'
		}
	}
	return report
}

fn earliest_date(days []DailyUsage) string {
	mut earliest := ''
	for day in days {
		if earliest == '' || day.date < earliest {
			earliest = day.date
		}
	}
	return earliest
}

fn median_of(values []f64) f64 {
	if values.len == 0 {
		return 0
	}
	mut sorted := values.clone()
	sorted.sort()
	middle := sorted.len / 2
	return if sorted.len % 2 == 1 {
		sorted[middle]
	} else {
		(sorted[middle - 1] + sorted[middle]) / 2
	}
}
