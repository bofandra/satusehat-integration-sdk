<?php
require __DIR__.'/../vendor/autoload.php';
use Satusehat\IntegrationSdk\Config;
use Satusehat\IntegrationSdk\SatusehatSdk;
$cfg=Config::fromEnv();
$sdk=new SatusehatSdk($cfg);
$payload=file_get_contents(__DIR__.'/../../../examples/fhir/encounter.json');
$id=$sdk->enqueue('POST','Encounter',null,$payload);
echo "queued $id\n";
echo "processed ".$sdk->processOnce(20)."\n";
