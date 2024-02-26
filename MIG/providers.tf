terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.16.0"
    }
  }
}


# Using "terraform service account" globally by mentioning its private key below. You can also use this block locally in the main.tf file.

provider "google" {
  # Configuration options

  project     = "terraform-on-gcp-414809" 
  credentials = "${file("ansible-sa-creds.json")}"
  # region
  # zone 
}