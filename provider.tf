terraform {
  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.11"
    }
  }
}

variable "elasticsearch_endpoint" {
  type    = string
  default = "your-endpoint"
}

variable "elasticsearch_api_key" {
  type      = string
  sensitive = true
  default   = "your-api_key"
}

variable "kibana_endpoint" {
  type    = string
  default = "your-endpoint"
}

variable "kibana_api_key" {
  type      = string
  sensitive = true
  default   = "your-api_key"
}

provider "elasticstack" {
  elasticsearch {
    endpoints = [var.elasticsearch_endpoint]
    api_key   = var.elasticsearch_api_key
  }
  kibana {
    endpoints = [var.kibana_endpoint]
    api_key   = var.kibana_api_key
  }
}
