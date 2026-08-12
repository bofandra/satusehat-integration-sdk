namespace Satusehat.IntegrationSdk;
public enum EventStatus { QUEUED, PROCESSING, SUCCESS, WAITING_FOR_CORRECTION, RATE_LIMITED, RETRYING, DEAD_LETTER, CANCELLED }
public sealed record FhirResponse(int StatusCode,string Body,IReadOnlyDictionary<string,string> Headers);
internal sealed record QueueEvent(string EventId,string Operation,string ResourceType,string? ResourceId,string? PayloadJson,int Attempt);
