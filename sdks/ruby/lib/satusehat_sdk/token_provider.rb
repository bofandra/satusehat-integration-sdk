require "json"
require "net/http"
require "thread"
require "uri"

module Satusehat
    module IntegrationSdk
        class TokenProvider
            def initialize(config)
                @config = config
                @token = nil
                @expires_at = Time.at(0)
                @mutex = Mutex.new
            end

            def invalidate
                @mutex.synchronize do
                    @token = nil
                    @expires_at = Time.at(0)
                end
            end

            def get_token
                @mutex.synchronize do
                    return @token if @token && Time.now < @expires_at - 60

                    fetch_token
                end
            end

            private

            def fetch_token
                uri = URI("#{@config.oauth_base_url}/accesstoken?grant_type=client_credentials")
                request = Net::HTTP::Post.new(uri)
                request["Accept"] = "application/json"
                request.set_form_data(
                    "client_id" => @config.client_id,
                    "client_secret" => @config.client_secret
                )

                response = Net::HTTP.start(
                    uri.host,
                    uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: @config.timeout_seconds,
                    read_timeout: @config.timeout_seconds
                ) { |http| http.request(request) }

                unless response.is_a?(Net::HTTPSuccess)
                    raise "OAuth HTTP #{response.code}: #{response.body.to_s[0, 1000]}"
                end

                body = JSON.parse(response.body.to_s)
                token = body["access_token"]
                raise "OAuth response does not contain access_token" if token.to_s.empty?

                @token = token
                @expires_at = Time.now + Integer(body.fetch("expires_in", 300))
                @token
            end
        end
    end
end
