# yii2-devops-deployment
# Yii2 DevOps Deployment

This project demonstrates a complete DevOps pipeline for deploying a Yii2 PHP application using Docker Swarm, NGINX reverse proxy, Ansible automation, and GitHub Actions CI/CD.

## Architecture

- **Application**: Yii2 PHP Framework
- **Containerization**: Docker + Docker Swarm
- **Reverse Proxy**: NGINX (host-based)
- **Infrastructure**: AWS EC2
- **Automation**: Ansible
- **CI/CD**: GitHub Actions
- **Monitoring**: Prometheus + Node Exporter
- **Registry**: GitHub Container Registry

## Quick Start

### Prerequisites
- AWS EC2 instance (Ubuntu 20.04 LTS)
- Docker Hub or GitHub Container Registry access
- Domain name or EC2 public IP
- SSH key pair for EC2 access

### GitHub Secrets Required
EC2_HOST=your.ec2.public.ip
EC2_USER=ubuntu
EC2_SSH_KEY=your-private-key-content
DOCKER_USERNAME=your-docker-username
DOCKER_PASSWORD=your-docker-password# yii2-devops-deployment
