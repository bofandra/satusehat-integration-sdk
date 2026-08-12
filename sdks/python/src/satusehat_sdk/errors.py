def classify_http(status: int) -> tuple[str, bool]:
    if 200 <= status <= 299:
        return "success", False
    if status == 401:
        return "unauthorized", True
    if status == 403:
        return "forbidden", False
    if status == 404:
        return "not_found", False
    if status == 409:
        return "conflict", False
    if status == 422:
        return "validation_error", False
    if status == 429:
        return "rate_limited", True
    if 500 <= status <= 599:
        return "server_error", True
    if 400 <= status <= 499:
        return "invalid_request", False
    return "unexpected_http_status", False
