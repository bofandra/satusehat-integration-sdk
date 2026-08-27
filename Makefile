.PHONY: validate python node java php go dotnet console-test console sandbox-contract sandbox-lab package-release

validate: python node java php go dotnet console-test
	@echo "Offline validations completed."

python:
	cd sdks/python && PYTHONPATH=src python3 -m pytest -q

node:
	cd sdks/node && npm test && npm run build

java:
	cd sdks/java && mvn test

php:
	find sdks/php -path sdks/php/vendor -prune -o -name '*.php' -print0 | xargs -0 -n1 php -l
	cd sdks/php && composer dump-autoload && composer test

go:
	cd sdks/go && go test ./...

dotnet:
	cd sdks/dotnet && dotnet build

console-test:
	python3 -m unittest tests/test_console.py -v

console:
	python3 services/console/server.py

sandbox-contract:
	PYTHONPATH=sdks/python/src python3 tools/sandbox_contract.py

sandbox-lab:
	tools/sandbox_lab_matrix.sh

package-release:
	mkdir -p dist
	cd sdks/python && python3 -m build && cp dist/* ../../dist/
	cd sdks/node && npm pack --pack-destination ../../dist
	cd sdks/java && mvn -Prelease -Dgpg.skip=true package && cp target/integration-sdk-0.2.0*.jar ../../dist/
	cd sdks/dotnet && dotnet pack -c Release && cp bin/Release/*.nupkg ../../dist/
