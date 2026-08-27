require "json"
require "satusehat_sdk"

sdk = nil

begin
    config = Satusehat::IntegrationSdk::Config.from_env
    sdk = Satusehat::IntegrationSdk::Client.new(config)

    payload = {
        "resourceType" => "Encounter",
        "status" => "finished"
    }

    event_id = sdk.enqueue(
        "POST",
        "Encounter",
        payload: payload,
        idempotency_key: "encounter:local-visit-123:create"
    )

    puts JSON.pretty_generate(
        "queued" => event_id,
        "processed" => sdk.process_once(20),
        "stats" => sdk.queue_stats
    )
ensure
    sdk&.close
end
