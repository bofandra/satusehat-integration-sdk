package id.kemkes.satusehat;

import static org.junit.jupiter.api.Assertions.*;
import org.junit.jupiter.api.Test;

class ErrorClassifierTest {
    @Test void classifiesSuccess() {
        var result = ErrorClassifier.classify(201);
        assertEquals("success", result.category());
        assertFalse(result.retryable());
    }

    @Test void classifiesRateLimitAsRetryable() {
        var result = ErrorClassifier.classify(429);
        assertEquals("rate_limited", result.category());
        assertTrue(result.retryable());
    }

    @Test void classifiesValidationAsNonRetryable() {
        var result = ErrorClassifier.classify(422);
        assertEquals("validation_error", result.category());
        assertFalse(result.retryable());
    }
}
