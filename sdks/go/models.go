package satusehat

type EventStatus string

const (
	Queued               EventStatus = "QUEUED"
	Processing           EventStatus = "PROCESSING"
	Success              EventStatus = "SUCCESS"
	WaitingForCorrection EventStatus = "WAITING_FOR_CORRECTION"
	RateLimited          EventStatus = "RATE_LIMITED"
	Retrying             EventStatus = "RETRYING"
	DeadLetter           EventStatus = "DEAD_LETTER"
	Cancelled            EventStatus = "CANCELLED"
)

type FHIRResponse struct {
	StatusCode int
	Body       []byte
	Headers    map[string]string
}
type Event struct {
	EventID, OrganizationID, Operation, ResourceType, ResourceID, PayloadJSON, Status string
	Attempt                                                                           int
	HTTPStatus                                                                        *int
	ErrorCategory, ErrorMessage, CreatedAt, UpdatedAt, NextRetryAt                    string
}
