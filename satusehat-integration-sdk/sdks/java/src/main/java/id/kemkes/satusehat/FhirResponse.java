package id.kemkes.satusehat;
import java.util.Map;
public record FhirResponse(int statusCode, String body, Map<String,String> headers) {}
