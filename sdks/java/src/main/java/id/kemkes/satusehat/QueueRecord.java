package id.kemkes.satusehat;

public record QueueRecord(
    String eventId,
    String organizationId,
    String idempotencyKey,
    String operation,
    String resourceType,
    String resourceId,
    String payloadJson,
    EventStatus status,
    int attempt,
    Integer httpStatus,
    String errorCategory,
    String errorMessage,
    String createdAt,
    String updatedAt,
    String nextRetryAt
) {}
