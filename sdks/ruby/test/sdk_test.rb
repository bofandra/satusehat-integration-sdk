require "minitest/autorun"
require "tmpdir"
require "time"
require "satusehat_sdk"

module SatusehatRubySdkTestHelpers
    def config(dir)
        Satusehat::IntegrationSdk::Config.new(
            client_id: "test-client",
            client_secret: "test-secret",
            organization_id: "10000001",
            queue_path: File.join(dir, "q.db"),
            rate_limit_rpm: 100_000
        )
    end

    def with_sdk
        Dir.mktmpdir do |dir|
            sdk = Satusehat::IntegrationSdk::Client.new(config(dir))
            begin
                yield sdk
            ensure
                sdk.close
            end
        end
    end

    def response(status, body = "", headers = {})
        Satusehat::IntegrationSdk::FhirResponse.new(
            status_code: status,
            body: body,
            headers: headers.transform_keys { |key| key.to_s.downcase }
        )
    end

    class StubFhir
        def initialize(response)
            @response = response
        end

        def request_once(*)
            @response
        end
    end
end

class SatusehatRubySdkTest < Minitest::Test
    include SatusehatRubySdkTestHelpers

    def test_classification
        classifier = Satusehat::IntegrationSdk::ErrorClassifier
        assert_equal ["success", false], classifier.classify(200)
        assert_equal ["rate_limited", true], classifier.classify(429)
        assert_equal ["server_error", true], classifier.classify(503)
        assert_equal ["validation_error", false], classifier.classify(422)
    end

    def test_enqueue_persists
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            row = sdk.queue.get(event_id)

            assert_equal Satusehat::IntegrationSdk::EventStatus::QUEUED, row["status"]
            assert_equal "Encounter", row["resource_type"]
            assert_equal event_id, row["correlation_id"]
            assert_equal 1, row["revision"]
        end
    end

    def test_queue_creates_canonical_v2_tables
        with_sdk do |sdk|
            columns = sdk.queue.db.execute("PRAGMA table_info(integration_events)").map { |row| row["name"] }
            tables = sdk.queue.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |row| row["name"] }

            assert_includes columns, "correlation_id"
            assert_includes columns, "superseded_by_event_id"
            assert_includes tables, "integration_event_history"
            assert_includes tables, "integration_notifications"
        end
    end

    def test_idempotent_enqueue_returns_existing_event
        with_sdk do |sdk|
            first = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"}, idempotency_key: "visit-1:create")
            second = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"}, idempotency_key: "visit-1:create")

            assert_equal first, second
            assert_equal 1, sdk.queue_stats["QUEUED"]
        end
    end

    def test_put_requires_id
        with_sdk do |sdk|
            assert_raises(ArgumentError) do
                sdk.enqueue("PUT", "Encounter", payload: {"resourceType" => "Encounter"})
            end
        end
    end

    def test_worker_success
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            sdk.instance_variable_set(:@fhir, SatusehatRubySdkTestHelpers::StubFhir.new(response(201, '{"id":"abc"}')))

            assert_equal 1, sdk.process_once(10)
            assert_equal "SUCCESS", sdk.queue.get(event_id)["status"]
        end
    end

    def test_worker_validation_error
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            sdk.instance_variable_set(:@fhir, SatusehatRubySdkTestHelpers::StubFhir.new(response(422, "bad data")))

            sdk.process_once(10)
            row = sdk.queue.get(event_id)
            assert_equal "WAITING_FOR_CORRECTION", row["status"]
            assert_equal "validation_error", row["error_category"]
        end
    end

    def test_dead_letter_admin_requeue
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            sdk.queue.complete(event_id, Satusehat::IntegrationSdk::EventStatus::DEAD_LETTER, 503, "server_error", "failed")

            letters = sdk.dead_letters
            assert_equal 1, letters.length
            assert_equal event_id, letters.first["event_id"]
            assert_equal true, sdk.requeue(event_id)

            row = sdk.queue.get(event_id)
            assert_equal "QUEUED", row["status"]
            assert_equal 0, row["attempt"]
        end
    end

    def test_worker_rate_limit
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            sdk.instance_variable_set(:@fhir, SatusehatRubySdkTestHelpers::StubFhir.new(response(429, "slow down", "Retry-After" => "1")))

            sdk.process_once(10)
            row = sdk.queue.get(event_id)
            assert_equal "RATE_LIMITED", row["status"]
            refute_nil row["next_retry_at"]
        end
    end

    def test_http_date_retry_after_is_supported
        with_sdk do |sdk|
            retry_after = (Time.now.utc + 5).httpdate
            delay = sdk.send(:backoff_seconds, 1, retry_after)

            assert_operator delay, :>, 0
            assert_operator delay, :<=, 5.5
        end
    end

    def test_stale_processing_event_is_recovered
        with_sdk do |sdk|
            event_id = sdk.enqueue("POST", "Encounter", payload: {"resourceType" => "Encounter"})
            sdk.queue.mark_processing(event_id)
            sdk.queue.db.execute(
                "UPDATE integration_events SET next_retry_at=? WHERE event_id=?",
                ["2000-01-01T00:00:00.000000Z", event_id]
            )

            assert_equal event_id, sdk.queue.ready(10).first["event_id"]
        end
    end
end
