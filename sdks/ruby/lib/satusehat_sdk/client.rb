require "date"
require "json"
require "net/http"
require "openssl"
require "socket"
require "thread"
require "time"

module Satusehat
    module IntegrationSdk
        class RateLimiter
            def initialize(rpm)
                @interval = 60.0 / rpm
                @last = 0.0
                @mutex = Mutex.new
            end

            def wait
                @mutex.synchronize do
                    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                    delay = @last + @interval - now
                    sleep(delay) if delay.positive?
                    @last = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                end
            end
        end

        class Client
            attr_reader :config, :tokens, :fhir, :queue

            TRANSIENT_ERRORS = [
                IOError,
                Net::OpenTimeout,
                Net::ReadTimeout,
                OpenSSL::SSL::SSLError,
                SocketError,
                SystemCallError,
                Timeout::Error
            ].freeze

            def initialize(config)
                @config = config
                @tokens = TokenProvider.new(config)
                @fhir = FhirClient.new(config, @tokens)
                @queue = SQLiteQueue.new(config.queue_path, config.processing_timeout_seconds)
                @rate = RateLimiter.new(config.rate_limit_rpm)
            end

            def close
                @queue.close
            end

            def enqueue(operation, resource_type, resource_id = nil, payload = nil, idempotency_key = nil, **kwargs)
                resource_id = kwargs[:resource_id] if kwargs.key?(:resource_id)
                payload = kwargs[:payload] if kwargs.key?(:payload)
                idempotency_key = kwargs[:idempotency_key] if kwargs.key?(:idempotency_key)
                @queue.enqueue(@config.organization_id, operation, resource_type, resource_id, payload, idempotency_key)
            end

            def queue_stats
                @queue.stats
            end

            def dead_letters(limit = 50)
                @queue.dead_letters(limit)
            end

            def requeue(event_id)
                @queue.requeue(event_id)
            end

            def request(operation, resource_type, resource_id = nil, payload = nil, **kwargs)
                resource_id = kwargs[:resource_id] if kwargs.key?(:resource_id)
                payload = kwargs[:payload] if kwargs.key?(:payload)
                last = nil

                1.upto(@config.max_retries) do |attempt|
                    @rate.wait
                    begin
                        response = @fhir.request_once(operation, resource_type, resource_id, payload)
                        @tokens.invalidate if response.status_code == 401

                        _category, retryable = ErrorClassifier.classify(response.status_code)
                        return response unless retryable && attempt < @config.max_retries

                        sleep(backoff_seconds(attempt, response.headers["retry-after"]))
                        last = response
                    rescue *TRANSIENT_ERRORS
                        raise if attempt >= @config.max_retries

                        sleep(backoff_seconds(attempt, nil))
                    end
                end

                last
            end

            def process_once(limit = 20)
                processed = 0
                @queue.ready(limit).each do |row|
                    processed += 1
                    event_id = row["event_id"]
                    attempt = @queue.mark_processing(event_id)

                    begin
                        payload = row["payload_json"] ? JSON.parse(row["payload_json"]) : nil
                        @rate.wait
                        response = @fhir.request_once(row["operation"], row["resource_type"], row["resource_id"], payload)
                        apply_response(event_id, attempt, response)
                    rescue *TRANSIENT_ERRORS => e
                        schedule_retry(event_id, attempt, "transport_error", e.message, nil, nil)
                    rescue StandardError => e
                        schedule_retry(event_id, attempt, "authentication_or_client_error", e.message, nil, nil)
                    end
                end
                processed
            end

            private

            def apply_response(event_id, attempt, response)
                status = response.status_code
                category, retryable = ErrorClassifier.classify(status)

                if status >= 200 && status <= 299
                    @queue.complete(event_id, EventStatus::SUCCESS, status)
                    return
                end

                @tokens.invalidate if status == 401

                if retryable
                    target = status == 429 ? EventStatus::RATE_LIMITED : EventStatus::RETRYING
                    schedule_retry(event_id, attempt, category, response.body, status, response.headers["retry-after"], target)
                    return
                end

                @queue.complete(event_id, EventStatus::WAITING_FOR_CORRECTION, status, category, response.body)
            end

            def schedule_retry(event_id, attempt, category, message, http_status, retry_after, target = EventStatus::RETRYING)
                if attempt >= @config.max_retries
                    @queue.complete(event_id, EventStatus::DEAD_LETTER, http_status, category, message)
                    return
                end

                next_retry_at = (Time.now.utc + backoff_seconds(attempt, retry_after)).iso8601(6)
                @queue.complete(event_id, target, http_status, category, message, next_retry_at)
            end

            def backoff_seconds(attempt, retry_after)
                retry_after = retry_after.to_s.strip unless retry_after.nil?
                if retry_after && !retry_after.empty?
                    begin
                        return [0.0, Float(retry_after)].max
                    rescue ArgumentError
                        begin
                            return [0.0, Time.httpdate(retry_after) - Time.now.utc].max
                        rescue ArgumentError
                            # Fall through to exponential backoff.
                        end
                    end
                end

                base_ms = [@config.max_backoff_ms, @config.initial_backoff_ms * (2**[attempt - 1, 0].max)].min
                jitter_ms = rand * [1000, base_ms * 0.2].min
                (base_ms + jitter_ms) / 1000.0
            end
        end
    end
end
