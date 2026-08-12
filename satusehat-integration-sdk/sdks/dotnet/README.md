# .NET / C# SDK

Targets .NET 8 and uses `HttpClient`, `System.Text.Json`, and `Microsoft.Data.Sqlite`.

```bash
dotnet restore
dotnet build
```

```csharp
var cfg = SatusehatConfig.FromEnvironment();
await using var sdk = new SatusehatSdk(cfg);
var eventId = sdk.Enqueue("POST", "Encounter", null, encounterJson);
await sdk.ProcessOnceAsync(20);
```
