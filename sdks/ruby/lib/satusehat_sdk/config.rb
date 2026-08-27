module Satusehat
    module IntegrationSdk
        class Config
            SANDBOX_OAUTH = "https://api-satusehat-stg.dto.kemkes.go.id/oauth2/v1"
            SANDBOX_FHIR = "https://api-satusehat-stg.dto.kemkes.go.id/fhir-r4/v1"
            PRODUCTION_OAUTH = "https://api-satusehat.kemkes.go.id/oauth2/v1"
            PRODUCTION_FHIR = "https://api-satusehat.kemkes.go.id/fhir-r4/v1"

            attr_reader :client_id, :client_secret, :organization_id, :environment,
                :queue_path, :timeout_seconds, :rate_limit_rpm, :max_retries,
                :processing_timeout_seconds, :initial_backoff_ms, :max_backoff_ms,
                :oauth_base_url_override, :fhir_base_url_override

            def initialize(
                client_id:,
                client_secret:,
                organization_id:,
                environment: "sandbox",
                queue_path: "./satusehat-sdk.db",
                timeout_seconds: 30,
                rate_limit_rpm: 300,
                max_retries: 5,
                processing_timeout_seconds: 300,
                initial_backoff_ms: 1000,
                max_backoff_ms: 60_000,
                oauth_base_url_override: nil,
                fhir_base_url_override: nil
            )
                @client_id = client_id.to_s
                @client_secret = client_secret.to_s
                @organization_id = organization_id.to_s
                @environment = environment.to_s.downcase
                @queue_path = queue_path.to_s
                @timeout_seconds = Integer(timeout_seconds)
                @rate_limit_rpm = Integer(rate_limit_rpm)
                @max_retries = Integer(max_retries)
                @processing_timeout_seconds = Integer(processing_timeout_seconds)
                @initial_backoff_ms = Integer(initial_backoff_ms)
                @max_backoff_ms = Integer(max_backoff_ms)
                @oauth_base_url_override = oauth_base_url_override
                @fhir_base_url_override = fhir_base_url_override
                validate!
            end

            def oauth_base_url
                (@oauth_base_url_override || (@environment == "production" ? PRODUCTION_OAUTH : SANDBOX_OAUTH)).sub(%r{/\z}, "")
            end

            def fhir_base_url
                (@fhir_base_url_override || (@environment == "production" ? PRODUCTION_FHIR : SANDBOX_FHIR)).sub(%r{/\z}, "")
            end

            def self.from_env(env = ENV)
                new(
                    client_id: env.fetch("SATUSEHAT_CLIENT_ID", ""),
                    client_secret: env.fetch("SATUSEHAT_CLIENT_SECRET", ""),
                    organization_id: env.fetch("SATUSEHAT_ORGANIZATION_ID", ""),
                    environment: env.fetch("SATUSEHAT_ENV", "sandbox"),
                    queue_path: env.fetch("SATUSEHAT_QUEUE_PATH", "./satusehat-sdk.db"),
                    timeout_seconds: env.fetch("SATUSEHAT_TIMEOUT_SECONDS", "30"),
                    rate_limit_rpm: env.fetch("SATUSEHAT_RATE_LIMIT_RPM", "300"),
                    max_retries: env.fetch("SATUSEHAT_MAX_RETRIES", "5"),
                    processing_timeout_seconds: env.fetch("SATUSEHAT_PROCESSING_TIMEOUT_SECONDS", "300"),
                    initial_backoff_ms: env.fetch("SATUSEHAT_INITIAL_BACKOFF_MS", "1000"),
                    max_backoff_ms: env.fetch("SATUSEHAT_MAX_BACKOFF_MS", "60000"),
                    oauth_base_url_override: env["SATUSEHAT_OAUTH_BASE_URL"],
                    fhir_base_url_override: env["SATUSEHAT_FHIR_BASE_URL"]
                )
            end

            private

            def validate!
                unless %w[sandbox production].include?(@environment)
                    raise ArgumentError, "environment must be sandbox or production"
                end
                if @client_id.empty? || @client_secret.empty? || @organization_id.empty?
                    raise ArgumentError, "client_id, client_secret, and organization_id are required"
                end

                positive = [
                    @timeout_seconds,
                    @rate_limit_rpm,
                    @max_retries,
                    @processing_timeout_seconds,
                    @initial_backoff_ms,
                    @max_backoff_ms
                ]
                raise ArgumentError, "numeric configuration values must be > 0" if positive.any? { |value| value <= 0 }
            end
        end
    end
end
