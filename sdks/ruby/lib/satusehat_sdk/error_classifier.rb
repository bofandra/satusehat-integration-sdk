module Satusehat
    module IntegrationSdk
        module ErrorClassifier
            module_function

            def classify(status)
                status = Integer(status)
                return ["success", false] if status >= 200 && status <= 299

                case status
                when 401 then ["unauthorized", true]
                when 403 then ["forbidden", false]
                when 404 then ["not_found", false]
                when 409 then ["conflict", false]
                when 422 then ["validation_error", false]
                when 429 then ["rate_limited", true]
                when 500..599 then ["server_error", true]
                when 400..499 then ["invalid_request", false]
                else ["unexpected_http_status", false]
                end
            end
        end
    end
end
