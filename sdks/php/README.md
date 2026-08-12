# PHP SDK

Requires PHP 8.2+, cURL, PDO, and PDO SQLite.

```bash
composer install
composer test
```

```php
use Satusehat\IntegrationSdk\Config;
use Satusehat\IntegrationSdk\SatusehatSdk;
$config = Config::fromEnv();
$sdk = new SatusehatSdk($config);
$eventId = $sdk->enqueue('POST','Encounter',null,json_encode(['resourceType'=>'Encounter']),'encounter:local-visit-123:create');
$sdk->processOnce(20);
$stats = $sdk->queueStats();
```
