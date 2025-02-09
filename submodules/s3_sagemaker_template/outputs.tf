output "file_id" {
  value = aws_s3_object.template_uploader.id
}

output "file_bucket" {
  value = aws_s3_bucket.sagemaker_template.id
}

output "s3_object_url" {
  value = "https://${aws_s3_bucket.sagemaker_template.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.template_uploader.key}"
}
