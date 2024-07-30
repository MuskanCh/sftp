variable "region" {
  description = "The AWS region to create resources in."
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "The name of the S3 bucket."
  default     = "sftps3bucket"
}
