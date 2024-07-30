provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "sftp_bucket" {
  bucket = var.bucket_name
}

resource "aws_iam_role" "ec2_sftp_role" {
  name = "ec2-sftp-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_sftp_policy" {
  name   = "ec2-sftp-policy"
  role   = aws_iam_role.ec2_sftp_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.sftp_bucket.arn,
        "${aws_s3_bucket.sftp_bucket.arn}/*"
      ]
    }]
  })
}

resource "aws_instance" "sftp_server" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"

  iam_instance_profile = aws_iam_instance_profile.ec2_sftp_instance_profile.name

  user_data = <<-EOF
              #!/bin/bash
              apt update -y
              apt install -y vsftpd python3
              systemctl start vsftpd
              systemctl enable vsftpd

              # Create an SFTP user
              useradd sftp-user1
              echo "sftpuser:numb@123" | chpasswd
              mkdir -p /home/sftp-user1/.ssh
              chmod 700 /home/sftp-user1/.ssh
              touch /home/sftp-user1/.ssh/authorized_keys
              chmod 600 /home/sftp-user1/.ssh/authorized_keys
              chown -R sftp-user1:sftpusers /home/sftp-user1/.ssh

              # Install boto3
              pip3 install boto3

              # Create S3 upload script
              cat << 'SCRIPT' > /home/sftp-user1/upload_to_s3.py
              import boto3
              import os

              s3_bucket_name = 'sftps3bucket'
              s3_folder_path = 'uploads'
              local_directory = '/home/sftp-user1/uploads'

              s3_client = boto3.client('s3')

              def upload_directory_to_s3(local_directory, bucket_name, s3_folder):
                  for root, dirs, files in os.walk(local_directory):
                      for filename in files:
                          local_path = os.path.join(root, filename)
                          relative_path = os.path.relpath(local_path, local_directory)
                          s3_path = os.path.join(s3_folder, relative_path)

                          try:
                              s3_client.upload_file(local_path, bucket_name, s3_path)
                              print(f"Successfully uploaded {local_path} to s3://{bucket_name}/{s3_path}")
                          except Exception as e:
                              print(f"Failed to upload {local_path} to S3: {e}")

              upload_directory_to_s3(local_directory, s3_bucket_name, s3_folder_path)
              SCRIPT

              chmod +x /home/sftpuser/upload_to_s3.py

              # Setup cron job to run script daily at midnight
              (crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/python3 /home/sftpuser/upload_to_s3.py") | crontab -

              mkdir -p /home/sftp-user1/uploads
              EOF

  tags = {
    Name = "SFTP Server"
  }
}

resource "aws_iam_instance_profile" "ec2_sftp_instance_profile" {
  name = "ec2-sftp-instance-profile"
  role = aws_iam_role.ec2_sftp_role.name
}

output "s3_bucket_name" {
  value = aws_s3_bucket.sftp_bucket.bucket
}

output "ec2_instance_id" {
  value = aws_instance.sftp_server.id
}

output "ec2_public_ip" {
  value = aws_instance.sftp_server.public_ip
}
