# Ruby SDK

Requires Ruby 3.1+ and the `sqlite3` gem.

```bash
bundle install
bundle exec rake test
```

```ruby
require "satusehat_sdk"

config = Satusehat::IntegrationSdk::Config.from_env
sdk = Satusehat::IntegrationSdk::Client.new(config)

event_id = sdk.enqueue(
    "POST",
    "Encounter",
    payload: {"resourceType" => "Encounter", "status" => "finished"},
    idempotency_key: "encounter:local-visit-123:create"
)

processed = sdk.process_once(20)
stats = sdk.queue_stats
sdk.close
```
