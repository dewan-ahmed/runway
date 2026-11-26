module main

import json

fn test_forecasts_devin_consumption() {
	content := '{"total_acus":40,"consumption_by_date":[
		{"date":1793505600,"acus":10},
		{"date":1793764800,"acus":30}
	]}'
	series := parse_devin(content) or {
		assert false, err.msg()
		return
	}
	result := forecast_usage(series, Options{
		source:       'devin'
		budget:       100
		period_start: '2026-11-01'
		period_end:   '2026-11-10'
		as_of:        '2026-11-04'
		warn_at:      80
		stop_at:      100
	}) or {
		assert false, err.msg()
		return
	}
	assert result.used == 40
	assert result.forecast == 100
	assert result.status == 'stop'
	assert result.exhaustion_date == '2026-11-10'
}

fn test_reads_factory_credits() {
	content := '{"data":[
		{"date":"2026-11-01","billable_tokens":10},
		{"date":"2026-11-05","billable_tokens":10}
	],"meta":{}}'
	series := parse_factory(content) or {
		assert false, err.msg()
		return
	}
	result := forecast_usage(series, Options{
		source:       'factory'
		budget:       100
		period_start: '2026-11-01'
		period_end:   '2026-11-10'
		as_of:        '2026-11-05'
		warn_at:      80
		stop_at:      100
	}) or {
		assert false, err.msg()
		return
	}
	assert result.unit == 'credits'
	assert result.forecast == 40
	assert result.status == 'ok'
}

fn test_reads_cosmos_credits_without_double_counting_empty_spans() {
	content := '{"resourceSpans":[{"scopeSpans":[{"spans":[
		{"startTimeUnixNano":"1793505600000000000","attributes":[
			{"key":"cosmos.credits","value":{"doubleValue":12.5}}
		]},
		{"startTimeUnixNano":"1793505600000000000","attributes":[
			{"key":"gen_ai.usage.input_tokens","value":{"intValue":"1000"}}
		]},
		{"startTimeUnixNano":"1793592000000000000","attributes":[
			{"key":"cosmos.credits","value":{"doubleValue":7.5}}
		]}
	]}]}]}'
	series := parse_cosmos(content, 'credits') or {
		assert false, err.msg()
		return
	}
	assert series.days.len == 2
	mut total := 0.0
	for day in series.days {
		total += day.amount
	}
	assert total == 20
}

fn test_warns_on_projected_threshold() {
	result := forecast_usage(UsageSeries{
		source: 'generic'
		unit:   'credits'
		days:   [
			DailyUsage{
				date:   '2026-11-01'
				amount: 9
			},
		]
	}, Options{
		budget:       100
		period_start: '2026-11-01'
		period_end:   '2026-11-10'
		as_of:        '2026-11-01'
		warn_at:      80
		stop_at:      100
	}) or {
		assert false, err.msg()
		return
	}
	assert result.forecast == 90
	assert result.status == 'warning'
}

fn synthetic_series(days int, base f64, last f64) UsageSeries {
	start := parse_date('2026-10-01') or { panic(err) }
	mut usage := []DailyUsage{}
	for i in 0 .. days {
		day := start.add_days(i)
		weekend := day.day_of_week() >= 6
		mut amount := if weekend { base / 4 } else { base + f64(i % 3) }
		if i == days - 1 {
			amount = last
		}
		usage << DailyUsage{
			date:   day.ymmdd()
			amount: amount
		}
	}
	return UsageSeries{
		source: 'devin'
		unit:   'acus'
		days:   usage
	}
}

fn test_detects_weekday_burn_spike() {
	// 2026-11-05 is a Thursday.
	report := detect_burn_spike(synthetic_series(36, 100, 400), AnomalyOptions{})!
	assert report.as_of == '2026-11-05'
	assert report.day_type == 'weekday'
	assert report.status == 'anomaly'
	assert report.reason_code == 'BURN_RATE_SPIKE'
	assert report.median == 101
}

fn test_normal_day_is_not_an_anomaly() {
	report := detect_burn_spike(synthetic_series(36, 100, 102), AnomalyOptions{})!
	assert report.status == 'ok'
	assert report.reason_code == ''
}

fn test_weekend_uses_weekend_baseline() {
	// 2026-11-01 is a Sunday: weekday-level usage is a spike on a weekend.
	report := detect_burn_spike(synthetic_series(32, 100, 100), AnomalyOptions{})!
	assert report.day_type == 'weekend'
	assert report.status == 'anomaly'
}

fn test_short_history_reports_insufficient_baseline() {
	report := detect_burn_spike(synthetic_series(10, 100, 400), AnomalyOptions{})!
	assert report.status == 'insufficient_baseline'
	assert report.reason_code == 'INSUFFICIENT_BASELINE'
}

fn test_anomaly_options_validation() {
	for args in [['--source', 'devin'], ['--source', 'devin', '--file', 'x', '--lookback', '3'],
		['--source', 'devin', '--file', 'x', '--threshold', '0'],
		['--bogus', 'x']] {
		if _ := parse_anomaly_options(args) {
			assert false, 'expected error for ${args}'
		}
	}
}

const session_spans = '{"resourceSpans":[{"scopeSpans":[{"spans":[
	{"startTimeUnixNano":"1793505600000000000","attributes":[{"key":"session.id","value":{"stringValue":"loop"}},{"key":"cosmos.credits","value":{"doubleValue":60}}]},
	{"startTimeUnixNano":"1793509200000000000","attributes":[{"key":"session.id","value":{"stringValue":"loop"}},{"key":"cosmos.credits","value":{"doubleValue":30}}]},
	{"startTimeUnixNano":"1793505600000000000","attributes":[{"key":"session.id","value":{"stringValue":"fix"}},{"key":"cosmos.credits","value":{"doubleValue":5}}]},
	{"startTimeUnixNano":"1793505600000000000","attributes":[{"key":"cosmos.credits","value":{"doubleValue":5}}]},
	{"startTimeUnixNano":"1793505600000000000","attributes":[{"key":"session.id","value":{"stringValue":"idle"}}]}
]}]}]}'

fn test_attributes_spend_to_sessions() {
	report := attribute_sessions(session_spans, SessionOptions{ session_cap: 50 })!
	assert report.total == 100
	assert report.groups == 3
	assert report.sessions.map(it.key) == ['loop', 'fix', 'unattributed']
	loop := report.sessions[0]
	assert loop.amount == 90
	assert loop.spans == 2
	assert loop.share == 90
	assert loop.reason_code == 'RUNAWAY_SESSION'
	assert loop.last_seen > loop.first_seen
	assert report.runaway == 1
	assert report.sessions[1].reason_code == ''
}

fn test_sessions_without_cap_and_with_top() {
	report := attribute_sessions(session_spans, SessionOptions{ top: 1 })!
	assert report.runaway == 0
	assert report.groups == 3
	assert report.sessions.len == 1
	assert !json.encode(report).contains('"first":')
}

fn test_sessions_options_validation() {
	for args in [['--file', 'x'], ['--source', 'devin', '--file', 'x'],
		['--source', 'cosmos'], ['--source', 'cosmos', '--file', 'x', '--top', '0'],
		['--source', 'cosmos', '--file', 'x', '--group-by', '']] {
		if _ := parse_session_options(args) {
			assert false, 'expected error for ${args}'
		}
	}
}
