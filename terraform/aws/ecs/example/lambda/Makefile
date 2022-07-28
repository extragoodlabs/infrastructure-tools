SHELL := /bin/bash

TF_VAR_service_name := jumpwire-example-crud-api
export TF_VAR_service_name

deploy:
	npx tailwindcss -i ./src/input.css -o ./templates/output.css
	cargo lambda build --release --workspace --arm64 --output-format=zip
	cp target/lambda/jumpwire-example-crud-api-default/bootstrap.zip release/jumpwire-example-crud-api-default.zip
	cp target/lambda/jumpwire-example-crud-api-customer/bootstrap.zip release/jumpwire-example-crud-api-customer.zip
	cp target/lambda/jumpwire-example-crud-api-staff/bootstrap.zip release/jumpwire-example-crud-api-staff.zip
	cd infrastructure \
  	&& terraform apply --auto-approve
