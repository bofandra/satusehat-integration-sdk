.PHONY: validate python node java php

validate: python node java php
	@echo "Offline validations completed. Go/.NET are validated in GitHub Actions where dependencies/runtimes are available."

python:
	cd sdks/python && PYTHONPATH=src python3 -m pytest -q

node:
	cd sdks/node && npm test && npm run build

java:
	@echo "Run: cd sdks/java && mvn test"

php:
	find sdks/php -name '*.php' -print0 | xargs -0 -n1 php -l
