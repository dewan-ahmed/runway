module main

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
