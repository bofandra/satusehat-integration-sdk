package satusehat

func ClassifyHTTP(status int) (string, bool) {
	switch {
	case status >= 200 && status <= 299:
		return "success", false
	case status == 401:
		return "unauthorized", true
	case status == 403:
		return "forbidden", false
	case status == 404:
		return "not_found", false
	case status == 409:
		return "conflict", false
	case status == 422:
		return "validation_error", false
	case status == 429:
		return "rate_limited", true
	case status >= 500 && status <= 599:
		return "server_error", true
	case status >= 400 && status <= 499:
		return "invalid_request", false
	default:
		return "unexpected_http_status", false
	}
}
