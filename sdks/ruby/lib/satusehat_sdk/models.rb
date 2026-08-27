module Satusehat
    module IntegrationSdk
        FhirResponse = Struct.new(:status_code, :body, :headers, keyword_init: true)
    end
end
