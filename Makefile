plan:
	terraform plan
apply:
	terraform apply -auto-approve
init:
	terraform init -upgrade
destroy:
	terraform destroy -auto-approve
fmt:
	terraform fmt -recursive