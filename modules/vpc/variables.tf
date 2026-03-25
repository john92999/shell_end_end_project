variable "vpc_cidr" {
    default = "10.0.0.0/16"
}

variable "public_cidrs" {
    default = ["10.0.1.0/24","10.0.2.0/24"]
}

variable "private_cidrs" {
    default = ["10.0.3.0/24","10.0.4.0/24"]
}

variable "data_cidrs" {
    default = ["10.0.5.0/24","10.0.6.0/24"]
}

variable "azs" {
    default = ["ap-south-1a","ap-south-1b"]
}

variable "env" {
    default = "dev"
}

variable "flow_log_role_arn" {

}

variable "flow_log_group_arn"{
    
}