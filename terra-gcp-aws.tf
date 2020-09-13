provider "google" {
  credentials = file("new-project.json")
  project     = var.project   
}

resource "google_compute_network" "myvpc" {
  name                    = var.vpc_gcp
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "network" {
  name          = var.lab
  ip_cidr_range = "10.0.1.0/24"
  region        = var.gcp_region
  network       = google_compute_network.myvpc.id  
}


resource "google_compute_firewall" "rule" {
  name    = "myfirewall"
  network = google_compute_network.myvpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

}


resource "google_container_cluster" "primary" {
  name               = "myk8scluster"
  location           = var.gcp_region
  initial_node_count = 1

  network    = google_compute_network.myvpc.name
  subnetwork = google_compute_subnetwork.network.name

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }
    
  }
 
}



data "google_client_config" "provider" {}


provider "kubernetes" { 
  load_config_file = false

  host  = "https://${google_container_cluster.primary.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
  )
}


resource "kubernetes_deployment" "wp" {
  metadata {
    name = "wordpress"
    labels = {
      App = "frontend"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        App = "frontend"
      }
    }
    template {
      metadata {
        labels = {
          App = "frontend"
        }
      }
      spec {
        container {
          image = "wordpress"
          name  = "wordpress"

          port {
            container_port = 80
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "lb" {
  metadata {
    name = "wordress"
  }
  spec {
    selector = {
      
      App = "frontend"
      
    }
    port {
      port        = 80
      target_port = 80
    }
    type = "LoadBalancer"
  } 
}


provider "aws" {
  region  = var.aws_region
  profile = var.profile 
}


resource "aws_security_group" "rds" {
  name        = "terraform_rds_security_group"
  description = "Terraform example RDS MySQL server"    
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    
  }
  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "terraform-example-rds-security-group"
  }
}


resource "aws_db_instance" "default" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = var.name
  username             = var.username
  password             = var.password
  parameter_group_name = "default.mysql5.7" 
  skip_final_snapshot  = true
  backup_retention_period = 0
  apply_immediately    = true
  publicly_accessible  = true  
  vpc_security_group_ids    = [aws_security_group.rds.id]
}

output "lb_ip" {
  value = kubernetes_service.lb.load_balancer_ingress.0.ip
}
output "dns" {
  value = aws_db_instance.default.address
}
output "name" {
  value = aws_db_instance.default.name
}
output "username" {
  value = aws_db_instance.default.username
}
output "password" {
  value = aws_db_instance.default.password
}