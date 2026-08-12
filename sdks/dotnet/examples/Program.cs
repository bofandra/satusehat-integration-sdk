using Satusehat.IntegrationSdk;
var cfg=SatusehatConfig.FromEnvironment();
await using var sdk=new SatusehatSdk(cfg);
var payload=await File.ReadAllTextAsync("../../examples/fhir/encounter.json");
var id=sdk.Enqueue("POST","Encounter",null,payload);
Console.WriteLine($"queued {id}");
Console.WriteLine($"processed {await sdk.ProcessOnceAsync(20)}");
