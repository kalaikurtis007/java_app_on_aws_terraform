variable "encrypt_key" {
  type        = string
  default     = "ec2_connect_key"
  description = "Name of the ssh key"
}

variable "certificate_arn" {
  type    = string
  default = "arn of certificate"

}