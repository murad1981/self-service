variable "project_id" {
  type        = string
  description = "GCP project ID (not the display name 'SelfService')."
}

variable "region" {
  type        = string
  default     = "me-central2"
  description = "Regional resource location. me-central2 (Dammam, KSA) is PDPL-preferred; this CNTXT-onboarded project uses it. me-central1 (Doha) is the standard-billing fallback."
}

variable "github_repo" {
  type        = string
  default     = "murad1981/self-service"
  description = "owner/name of the GitHub repo allowed to assume the deploy SA via WIF."
}

variable "envs" {
  type        = list(string)
  default     = ["qa", "staging", "production"]
  description = "Environments (single-project model: separated by resource naming + IAM)."
}

variable "prefix" {
  type    = string
  default = "selfserve"
}

variable "ar_repo" {
  type    = string
  default = "selfserve-docker"
}

variable "wif_pool" {
  type    = string
  default = "github-pool"
}

variable "wif_provider" {
  type    = string
  default = "github-provider"
}

variable "secret_names" {
  type    = list(string)
  default = ["jwt-signing-key", "db-password", "firebase-admin-key", "nafath-app-id", "nafath-app-key"]
}

variable "kms_keys" {
  type    = list(string)
  default = ["pii", "biometric", "location"]
}
