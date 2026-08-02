variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "admin_cidr" {
  description = "Your public IP address in CIDR format"
  type        = string
}

variable "public_key_path" {
  description = "Path to the local SSH public key"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "jenkins_instance_type" {
  description = "Jenkins controller EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "agent_instance_type" {
  description = "Jenkins agent EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "sonarqube_instance_type" {
  description = "SonarQube EC2 instance type"
  type        = string
  default     = "t3.large"
}
