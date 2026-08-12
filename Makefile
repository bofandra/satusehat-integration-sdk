.PHONY: validate python node java php go dotnet sandbox-contract package-release

validate: python node java php go dotnet
	@echo "Offline validations completed."

python:
	cd sdks/python && PYTHONPATH=src python3 -m pytest -q

node:
	cd sdks/node && npm test && npm run build

java:
	cd sdks/java && mvn test

php:
	find sdks/php -name '*.php' -print0 | xargs -0 -n1 php -l

go:
	cd sdks/go && go test ./...

dotnet:
	cd sdks/dotnet && dotnet build

sandbox-contract:
	PYTHONPATH=sdks/python/src python3 tools/sandbox_contract.py

package-release:
	mkdir -p dist
	cd sdks/python && python3 -m build && cp dist/* ../../dist/
	cd sdks/node && npm pack --pack-destination ../../dist
	cd sdks/java && mvn -Prelease -Dgpg.skip=true package && cp target/integration-sdk-0.1.0*.jar ../../dist/
	cd sdks/dotnet && dotnet pack -c Release && cp bin/Release/*.nupkg ../../dist/
