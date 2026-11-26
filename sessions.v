module main

import json
import strconv
import time

struct SessionOptions {
	file        string
	measure     string = 'credits'
	group_by    string = 'session.id'
	session_cap f64
	top         int = 10
}

struct SessionUsage {
	key         string
	amount      f64
	spans       int
	first_seen  string
	last_seen   string
	share       f64
	reason_code string
mut:
	first i64 @[json: '-']
	last  i64 @[json: '-']
}

struct SessionReport {
	version  int = 1
	source   string
	unit     string
	group_by string
	total    f64
	groups   int
	runaway  int
	sessions []SessionUsage
}

fn parse_session_options(args []string) !SessionOptions {
	mut values := map[string]string{}
	mut index := 0
	for index < args.len {
		flag := args[index]
		if flag !in ['--source', '--file', '--measure', '--group-by', '--session-cap', '--top'] {
			return error('unknown option "${flag}"')
		}
		if index + 1 >= args.len {
			return error('${flag} requires a value')
		}
		values[flag] = args[index + 1]
		index += 2
	}
	if (values['--source'] or { '' }) != 'cosmos' {
		return error('sessions requires --source cosmos')
	}
	if values['--file'] == '' {
		return error('sessions requires --file')
	}
	options := SessionOptions{
		file:        values['--file']
		measure:     values['--measure'] or { 'credits' }
		group_by:    values['--group-by'] or { 'session.id' }
		session_cap: (values['--session-cap'] or { '0' }).f64()
		top:         (values['--top'] or { '10' }).int()
	}
	if options.group_by == '' {
		return error('--group-by must not be empty')
	}
	if options.session_cap < 0 || options.top < 1 {
		return error('--session-cap must be >= 0 and --top must be >= 1')
	}
	return options
}

// attribute_sessions sums Cosmos spend per --group-by span attribute. Spans
// without the attribute are reported as `unattributed` so totals reconcile.
fn attribute_sessions(content string, options SessionOptions) !SessionReport {
	attribute := match options.measure {
		'credits' { 'cosmos.credits' }
		'cost' { 'cosmos.cost_usd' }
		else { return error('Cosmos measure must be "credits" or "cost"') }
	}

	export := json.decode(OtlpExport, content)!
	mut groups := map[string]SessionUsage{}
	mut total := 0.0
	for resource in export.resource_spans {
		for scope in resource.scope_spans {
			for span in scope.spans {
				mut amount := 0.0
				mut found := false
				mut key := 'unattributed'
				for item in span.attributes {
					if item.key == attribute {
						amount += item.value.double_value
						found = true
					} else if item.key == options.group_by {
						value := if item.value.string_value != '' {
							item.value.string_value
						} else {
							item.value.int_value
						}
						if value != '' {
							key = value
						}
					}
				}
				if !found {
					continue
				}
				seconds := if span.start_time_unix_nano.len >= 10 {
					strconv.parse_int(span.start_time_unix_nano[..10], 10, 64) or { 0 }
				} else {
					i64(0)
				}
				mut group := groups[key] or {
					SessionUsage{
						key:   key
						first: seconds
						last:  seconds
					}
				}
				group = SessionUsage{
					...group
					amount: group.amount + amount
					spans:  group.spans + 1
					first:  if seconds < group.first { seconds } else { group.first }
					last:   if seconds > group.last { seconds } else { group.last }
				}
				groups[key] = group
				total += amount
			}
		}
	}
	if groups.len == 0 {
		return error('Cosmos input has no ${attribute} span attributes')
	}
	mut sessions := []SessionUsage{}
	mut runaway := 0
	for _, group in groups {
		over := options.session_cap > 0 && group.amount > options.session_cap
		if over {
			runaway++
		}
		sessions << SessionUsage{
			...group
			amount:      round2(group.amount)
			share:       if total > 0 { round2(group.amount / total * 100.0) } else { 0.0 }
			first_seen:  time.unix(group.first).format_ss()
			last_seen:   time.unix(group.last).format_ss()
			reason_code: if over { 'RUNAWAY_SESSION' } else { '' }
		}
	}
	sessions.sort_with_compare(fn (a &SessionUsage, b &SessionUsage) int {
		if a.amount != b.amount {
			return if a.amount > b.amount { -1 } else { 1 }
		}
		return compare_strings(a.key, b.key)
	})
	return SessionReport{
		source:   'cosmos'
		unit:     if options.measure == 'cost' { 'USD' } else { 'credits' }
		group_by: options.group_by
		total:    round2(total)
		groups:   sessions.len
		runaway:  runaway
		sessions: if sessions.len > options.top { sessions[..options.top] } else { sessions }
	}
}
