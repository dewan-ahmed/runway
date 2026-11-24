module main

import json
import os
import strconv

fn main() {
	if os.args.len < 2 || os.args[1] in ['help', '--help', '-h'] {
		print_help()
		return
	}
	if os.args[1] != 'check' {
		eprintln('runway: unknown command "${os.args[1]}"')
		exit(3)
	}
	options := parse_options(os.args[2..]) or {
		eprintln('runway: ${err}')
		exit(3)
	}
	series := load_usage(options) or {
		eprintln('runway: ${err}')
		exit(3)
	}
	result := forecast_usage(series, options) or {
		eprintln('runway: ${err}')
		exit(3)
	}
	println(json.encode(result))
	match result.status {
		'warning' { exit(1) }
		'stop' { exit(2) }
		else {}
	}
}

fn parse_options(args []string) !Options {
	mut source := ''
	mut file := ''
	mut budget := 0.0
	mut period_start := ''
	mut period_end := ''
	mut as_of := ''
	mut warn_at := 80.0
	mut stop_at := 100.0
	mut measure := 'credits'
	mut index := 0
	for index < args.len {
		if index + 1 >= args.len {
			return error('${args[index]} requires a value')
		}
		value := args[index + 1]
		match args[index] {
			'--source' { source = value }
			'--file', '-f' { file = value }
			'--budget' { budget = strconv.atof64(value)! }
			'--period-start' { period_start = value }
			'--period-end' { period_end = value }
			'--as-of' { as_of = value }
			'--warn-at' { warn_at = strconv.atof64(value)! }
			'--stop-at' { stop_at = strconv.atof64(value)! }
			'--measure' { measure = value }
			else { return error('unknown option "${args[index]}"') }
		}

		index += 2
	}
	if source == '' || file == '' || period_start == '' || period_end == '' || budget == 0 {
		return error('check requires --source, --file, --budget, --period-start, and --period-end')
	}
	return Options{
		source:       source
		file:         file
		budget:       budget
		period_start: period_start
		period_end:   period_end
		as_of:        as_of
		warn_at:      warn_at
		stop_at:      stop_at
		measure:      measure
	}
}

fn print_help() {
	println('runway forecasts software-factory usage against a budget.')
	println('')
	println('Usage:')
	println('  runway check --source devin|factory|cosmos --file PATH --budget NUMBER \\')
	println('    --period-start YYYY-MM-DD --period-end YYYY-MM-DD [options]')
	println('')
	println('Options:')
	println('  --as-of YYYY-MM-DD      Forecast from this date (default: latest input date)')
	println('  --warn-at PERCENT       Warning threshold (default: 80)')
	println('  --stop-at PERCENT       Stop threshold (default: 100)')
	println('  --measure credits|cost  Cosmos measure (default: credits)')
}
