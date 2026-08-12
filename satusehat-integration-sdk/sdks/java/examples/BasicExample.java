import id.kemkes.satusehat.*;
import java.nio.file.*;
public class BasicExample {
  public static void main(String[] args) throws Exception {
    var cfg=SatusehatConfig.fromEnv();
    var payload=Files.readString(Path.of("../../examples/fhir/encounter.json"));
    try(var sdk=new SatusehatSdk(cfg)){
      var id=sdk.enqueue("POST","Encounter",null,payload);
      System.out.println("queued "+id);
      System.out.println("processed "+sdk.processOnce(20));
    }
  }
}
