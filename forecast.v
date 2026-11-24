module main

import math
import time

fn forecast_usage(series UsageSeries, options Options) !Forecast {
	start := parse_date(options.period_start)!
	end := parse_date(options.period_end)!
	if end.unix() < start.unix() {
		return error('period end must not be before period start')
	}
	as_of_value := if options.as_of != '' { options.as_of } else { latest_date(series.days)! }
	as_of := parse_date(as_of_value)!
	if as_of.unix() < start.unix() || as_of.unix() > end.unix() {
		return error('as-of date must fall inside the budget period')
	}
	if options.budget <= 0 {
		return error('budget must be greater than zero')
	}
	if options.warn_at <= 0 || options.stop_at <= options.warn_at {
		return error('thresholds require 0 < warn-at < stop-at')
	}
	mut used := 0.0
	for day in series.days {
		date := parse_date(day.date)!
		if date.unix() >= start.unix() && date.unix() <= as_of.unix() {
			used += day.amount
		}
	}
	elapsed_days := days_inclusive(start, as_of)
	period_days := days_inclusive(start, end)
	daily_rate := used / f64(elapsed_days)
	projected := daily_rate * f64(period_days)
	used_percent := used / options.budget * 100.0
	forecast_percent := projected / options.budget * 100.0
	remaining := math.max(options.budget - used, 0.0)
	runway_days := if daily_rate > 0 { remaining / daily_rate } else { 0.0 }
	mut exhaustion_date := ''
	if daily_rate > 0 {
		days_to_budget := int(math.ceil(options.budget / daily_rate)) - 1
		exhaustion := start.add_days(days_to_budget)
		if exhaustion.unix() <= end.unix() {
			exhaustion_date = exhaustion.ymmdd()
		}
	}
	status := if forecast_percent >= options.stop_at {
		'stop'
	} else if forecast_percent >= options.warn_at {
		'warning'
	} else {
		'ok'
	}
	return Forecast{
		source:           series.source
		unit:             series.unit
		period_start:     options.period_start
		period_end:       options.period_end
		as_of:            as_of_value
		elapsed_days:     elapsed_days
		period_days:      period_days
		used:             round2(used)
		budget:           round2(options.budget)
		used_percent:     round2(used_percent)
		daily_rate:       round2(daily_rate)
		forecast:         round2(projected)
		forecast_percent: round2(forecast_percent)
		remaining:        round2(remaining)
		runway_days:      round2(runway_days)
		exhaustion_date:  exhaustion_date
		status:           status
	}
}

fn parse_date(value string) !time.Time {
	if value.len != 10 {
		return error('invalid date "${value}", expected YYYY-MM-DD')
	}
	return time.parse('${value} 00:00:00')
}

fn latest_date(days []DailyUsage) !string {
	if days.len == 0 {
		return error('usage input has no dated entries')
	}
	mut latest := days[0].date
	for day in days[1..] {
		if day.date > latest {
			latest = day.date
		}
	}
	return latest
}

fn days_inclusive(start time.Time, end time.Time) int {
	return int((end.unix() - start.unix()) / 86400) + 1
}

fn round2(value f64) f64 {
	return math.round(value * 100.0) / 100.0
}
