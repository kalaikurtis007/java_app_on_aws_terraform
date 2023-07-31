## Hint to create vpc in AWS
1. select the region
2. create vpc
3. enable DNS hostname in the VPC
4. crate Internet Gateway
5. Attach Internet Gateway to VPC
6. Create Public Subnets.
7. Enable auto assign public Ip Settings
8. create public route table
9. add public route to the pubic route table
10. associate the public subnets with the public route table
11. create the private subnets
12. create nat gateway
13. create an EIP and associate it to the nat gateways
14. create private route table
15. Add pubic route to the private route table
16. Associate the Private Subnets with the Private Route table.


terraform plan -out ouput.tfplan

terraform show -no-color -json output.tfplan > output.json

terraform apply/destroy  -auto-approve
