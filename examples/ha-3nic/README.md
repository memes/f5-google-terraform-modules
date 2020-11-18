# High Availability sub-module with 3-NIC deployment

This example demonstrates how to use the
[HA sub-module](https://registry.terraform.io/modules/memes/f5-bigip/google/latest/submodules/ha)
to deploy a pair of BIG-IP instances in a 3-NIC configuration.

> **NOTE:** This example does not include firewall rules, ingress routes, or any
> other dependencies needed to for a fully-functional deployment. The intent is
> only to demonstrate how to *add* an HA BIG-IP component to a broader
> deployment.

![ha-3nic](ha-3nic.png)

<!-- spell-checker: ignore tfvars gserviceaccount mgmt bigip -->
## Example tfvars file

* Deploy to project: `my-project-id`
* Deploy BIG-IPs to zone: `us-west1-c`
* Assign BIG-IP data-plane (external) to VPC: `external` in `us-west1` subnet `ext-west`
* Assign BIG-IP control-plane to VPC: `management` in `us-west1` subnet `mgmt-west`
* Assign BIG-IP data-plane (internal) to VPC: `internal` in `us-west1` subnet `int-west`
* BIG-IP will use service account: `bigip@my-project-id.iam.gserviceaccount.com`
* BIG-IP admin user password is stored in Secret Manager under the key:
  `bigip-admin-password-key`

<!-- spell-checker: disable -->
```hcl
project_id         = "my-project-id"
zone               = "us-west1-c"
external_network   = "https://www.googleapis.com/compute/v1/projects/my-project-id/global/networks/external"
external_subnet    = "https://www.googleapis.com/compute/v1/projects/my-project-id/regions/us-west1/subnetworks/ext-west"
management_network = "https://www.googleapis.com/compute/v1/projects/my-project-id/global/networks/management"
management_subnet  = "https://www.googleapis.com/compute/v1/projects/my-project-id/regions/us-west1/subnetworks/mgmt-west"
internal_network   = "https://www.googleapis.com/compute/v1/projects/my-project-id/global/networks/internal"
internal_subnet    = "https://www.googleapis.com/compute/v1/projects/my-project-id/regions/us-west1/subnetworks/int-west"
admin_password_key = "bigip-admin-password-key"
service_account    = "bigip@my-project-id.iam.gserviceaccount.com"
```
<!-- spell-checker: enable -->

### Prerequisites

* VPC networks for `external`, `management`, and `internal` with subnets in
  region where the BIG-IPs will be deployed
* Service account to be used by BIG-IP VMs
* BIG-IP admin account password stored in Secret Manager, with `read` access
  granted to BIG-IP service account

### Resources created

<!-- spell-checker: ignore payg -->
* 2x VMs running BIG-IP v15.1 PAYG license
* 2 reserved internal IP addresses on `external` VPC network; these will be
  assigned to external interface on BIG-IP instances
* 2 reserved internal IP addresses on `management` VPC network; these will be
  assigned to management interface on BIG-IP instances
* 2 reserved internal IP addresses on `internal` VPC network; these will be
  assigned to internal interface on BIG-IP instances
* Firewall rules to permit BIG-IP ConfigSync traffic on `management` and
  `external` VPC networks, limited to VMs using BIG-IP service account

<!-- spell-checker:ignore markdownlint -->
<!-- markdownlint-disable MD033 MD034-->
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- markdownlint-enable MD033 MD034 -->
