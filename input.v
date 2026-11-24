module main

import json
import os
import strconv
import time

struct DevinConsumption {
	total_acus          f64
	consumption_by_date []DevinDay
}

struct DevinDay {
	date int
	acus f64
}

struct FactoryConsumption {
	data []FactoryDay
}

struct FactoryDay {
	date            string
	billable_tokens f64
}

struct OtlpExport {
	resource_spans []OtlpResourceSpans @[json: resourceSpans]
}

struct OtlpResourceSpans {
	scope_spans []OtlpScopeSpans @[json: scopeSpans]
}

struct OtlpScopeSpans {
	spans []OtlpSpan
}

struct OtlpSpan {
	start_time_unix_nano string @[json: startTimeUnixNano]
	attributes           []OtlpKeyValue
}

struct OtlpKeyValue {
	key   string
	value OtlpAnyValue
}

struct OtlpAnyValue {
	string_value string @[json: stringValue]
	int_value    string @[json: intValue]
	double_value f64    @[json: doubleValue]
}

fn load_usage(options Options) !UsageSeries {
	content := if options.file == '-' {
		os.get_raw_lines_joined()
	} else {
		os.read_file(options.file)!
	}
	return match options.source {
		'devin' { parse_devin(content)! }
		'factory' { parse_factory(content)! }
		'cosmos' { parse_cosmos(content, options.measure)! }
		else { error('unsupported source "${options.source}"') }
	}
}

fn parse_devin(content string) !UsageSeries {
	response := json.decode(DevinConsumption, content)!
	mut days := []DailyUsage{}
	for entry in response.consumption_by_date {
		days << DailyUsage{
			date:   time.unix(i64(entry.date)).ymmdd()
			amount: entry.acus
		}
	}
	if days.len == 0 {
		return error('Devin input has no consumption_by_date entries')
	}
	return UsageSeries{
		source: 'devin'
		unit:   'ACU'
		days:   days
	}
}

fn parse_factory(content string) !UsageSeries {
	response := json.decode(FactoryConsumption, content)!
	mut days := []DailyUsage{}
	for entry in response.data {
		if entry.date != '' {
			days << DailyUsage{
				date:   entry.date
				amount: entry.billable_tokens
			}
		}
	}
	if days.len == 0 {
		return error('Factory input has no dated data entries')
	}
	return UsageSeries{
		source: 'factory'
		unit:   'credits'
		days:   days
	}
}

fn parse_cosmos(content string, measure string) !UsageSeries {
	attribute := match measure {
		'credits' { 'cosmos.credits' }
		'cost' { 'cosmos.cost_usd' }
		else { return error('Cosmos measure must be "credits" or "cost"') }
	}

	export := json.decode(OtlpExport, content)!
	mut totals := map[string]f64{}
	for resource in export.resource_spans {
		for scope in resource.scope_spans {
			for span in scope.spans {
				if span.start_time_unix_nano.len < 10 {
					continue
				}
				seconds := strconv.parse_int(span.start_time_unix_nano[..10], 10, 64) or {
					continue
				}
				for item in span.attributes {
					if item.key == attribute {
						date := time.unix(seconds).ymmdd()
						totals[date] += item.value.double_value
					}
				}
			}
		}
	}
	mut days := []DailyUsage{}
	for date, amount in totals {
		days << DailyUsage{
			date:   date
			amount: amount
		}
	}
	if days.len == 0 {
		return error('Cosmos input has no ${attribute} span attributes')
	}
	return UsageSeries{
		source: 'cosmos'
		unit:   if measure == 'cost' { 'USD' } else { 'credits' }
		days:   days
	}
}
