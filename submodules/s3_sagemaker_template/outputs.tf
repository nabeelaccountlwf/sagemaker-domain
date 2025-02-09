output "tar_file_id" {
  value = aws_s3_object.autoshutdown_tar_upload.id
}

output "tar_file_bucket" {
  value = aws_s3_object.autoshutdown_tar_upload.id
}

output "s3_object_url" {
  value = "https://${aws_s3_bucket.sagemaker_output_bucket.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.template_uploader.key}"
}
