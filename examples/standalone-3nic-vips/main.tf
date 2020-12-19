# Example Terraform to create a three-NIC instance of BIG-IP using default
# compute service account, and a Marketplace PAYG image.
#
# Note: values to be updated by implementor are shown as [ITEM], where ITEM should
# be changed to the correct resource name/identifier.

# Only supported on Terraform 0.13 and Terraform 0.14
terraform {
  required_version = "> 0.12"
}

module "instance" {
  /* TODO @memes
  source                = "memes/f5-bigip/google"
  version               = "2.0.2"
  */
  source                        = "../../"
  project_id                    = var.project_id
  num_instances                 = var.num_instances
  zones                         = [var.zone]
  service_account               = var.service_account
  external_subnetwork           = var.external_subnet
  external_subnetwork_vip_cidrs = var.external_vips
  management_subnetwork         = var.management_subnet
  # BIG-IP template accepts 1-6 NICs for internal network, just pass in a list
  # of self-links
  internal_subnetworks              = [var.internal_subnet]
  image                             = var.image
  allow_phone_home                  = false
  admin_password_secret_manager_key = var.admin_password_key
}
