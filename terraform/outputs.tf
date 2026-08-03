output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "agent_public_ip" {
  value = aws_instance.agent.public_ip
}

output "agent_private_ip" {
  value = aws_instance.agent.private_ip
}

output "sonarqube_public_ip" {
  value = aws_instance.sonarqube.public_ip
}

output "sonarqube_private_ip" {
  value = aws_instance.sonarqube.private_ip
}

output "sonarqube_url" {
  value = "http://${aws_instance.sonarqube.public_ip}:9000"
}

output "eks_cluster_name" {
  value = aws_eks_cluster.devsecops.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.devsecops.endpoint
}

output "eks_node_group_name" {
  value = aws_eks_node_group.devsecops.node_group_name
}
