require "json"
require "net/http"
require "uri"

module Satusehat
    module IntegrationSdk
        class FhirClient
            METHODS = {
                "GET" => Net::HTTP::Get,
                "POST" => Net::HTTP::Post,
                "PUT" => Net::HTTP::Put,
                "PATCH" => Net::HTTP::Patch
            }.freeze

            def initialize(config, token_provider)
                @config = config
                @tokens = token_provider
            end

            def request_once(method, resource_type, resource_id = nil, payload = nil)
                method = method.to_s.upcase
                request_class = METHODS.fetch(method) { raise ArgumentError, "unsupported operation" }
                uri = URI("#{@config.fhir_base_url}/#{resource_type}")
                uri = URI("#{uri}/#{resource_id}") if resource_id && !resource_id.to_s.empty?

                request = request_class.new(uri)
                request["Authorization"] = "Bearer #{@tokens.get_token}"
                request["Accept"] = "application/fhir+json, application/json"
                request["Content-Type"] = method == "PATCH" ? "application/json" : "application/fhir+json"
                request.body = serialize_payload(payload) unless payload.nil?

                response = perform(uri, request)
                FhirResponse.new(
                    status_code: response.code.to_i,
                    body: response.body.to_s,
                    headers: normalized_headers(response)
                )
            end

            private

            def perform(uri, request)
                Net::HTTP.start(
                    uri.host,
                    uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: @config.timeout_seconds,
                    read_timeout: @config.timeout_seconds
                ) { |http| http.request(request) }
            end

            def serialize_payload(payload)
                if payload.is_a?(String)
                    JSON.parse(payload)
                    payload
                else
                    JSON.generate(payload)
                end
            end

            def normalized_headers(response)
                headers = {}
                response.each_header { |key, value| headers[key.downcase] = value }
                headers
            end
        end
    end
end
