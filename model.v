module main

struct Options {
	source       string
	file         string
	budget       f64
	period_start string
	period_end   string
	as_of        string
	warn_at      f64    = 80.0
	stop_at      f64    = 100.0
	measure      string = 'credits'
}

struct DailyUsage {
	date   string
	amount f64
}

struct UsageSeries {
	source string
	unit   string
	days   []DailyUsage
}

struct Forecast {
	version          int = 1
	source           string
	unit             string
	period_start     string
	period_end       string
	as_of            string
	elapsed_days     int
	period_days      int
	used             f64
	budget           f64
	used_percent     f64
	daily_rate       f64
	forecast         f64
	forecast_percent f64
	remaining        f64
	runway_days      f64
	exhaustion_date  string
	status           string
}
