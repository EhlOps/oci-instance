# OCI instance (4 OCPU / 24 GB)

One `VM.Standard.A1.Flex` (Ampere, arm64) instance running Oracle Linux 10, with Docker installed by cloud-init. It sits in a new VCN with a public subnet. Ports 22, 80 and 443 are open.

## Setup
1. `brew install terraform oci-cli`
2. `oci setup config`, then upload the generated public API key in the OCI console.
3. `cp terraform.tfvars.example terraform.tfvars` and fill in `tenancy_ocid` and `region`. Set `ssh_allowed_cidr` to your own IP.
4. `terraform init && terraform plan && terraform apply`

## Verify
```
ssh opc@$(terraform output -raw public_ip)
cloud-init status --wait
docker run --rm hello-world
nproc && free -g
```

## Notes
- "Out of host capacity" on apply is common for A1. Try another `availability_domain_index` or retry later.
- Images are arm64, so use arm64 or multi-arch container images.
