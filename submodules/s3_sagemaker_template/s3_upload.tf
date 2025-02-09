data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "sagemaker_template" {
  bucket = "lwf-sagemaker-storage-${data.aws_region.current.name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sagemaker_template" {
  bucket = aws_s3_bucket.sagemaker_template.bucket
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "block_public_auto_shutdown" {
  bucket                  = aws_s3_bucket.sagemaker_template.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "sagemaker_template_life_cycle_config" {
  bucket = aws_s3_bucket.sagemaker_template.id

  rule {
    id = "life-cycle-configuration-rule"
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "sagemaker_template_access_log" {
  bucket = aws_s3_bucket.sagemaker_template.id

  target_bucket = aws_s3_bucket.sagemaker_template.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_versioning" "sagemaker_template_versioning" {
  bucket = aws_s3_bucket.sagemaker_template.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "template_uploader" {
  bucket     = aws_s3_bucket.sagemaker_template.id
  key        = "sagemaker_template/template.yml"
  source     = "${path.module}/../../assets/sagemaker_template/template.yml"
  kms_key_id = var.kms_arn

  # Checks hash to enusre if file is changed, it's updated in S3
  source_hash       = filemd5("${path.module}/../../assets/sagemaker_template/template.yml")
}

