data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# --------------------------------------------------------------------------------------------
# KMS KEYS
# --------------------------------------------------------------------------------------------
resource "aws_kms_key" "sagemaker_efs_kms_key" {
  description         = "KMS key used to encrypt SageMaker Studio EFS volume"
  enable_key_rotation = true
}

resource "aws_kms_key_policy" "example" {
  key_id = aws_kms_key.sagemaker_efs_kms_key.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "expanded-kms-policy"
    Statement = [
      # Allow full control of the key to the AWS account root user
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = [data.aws_caller_identity.current.account_id]
        }
        Action   = "kms:*"
        Resource = "*"
      },

      # Allow the IAM user "ci-user" to use KMS for encryption & decryption
      {
        Sid    = "AllowCIUserKMSAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/ci-user"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },

      # Allow S3 to use the key for encrypted object storage
      {
        Sid    = "AllowS3Access"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },

      # Allow SageMaker to use the key for EFS and S3 encrypted storage
      {
        Sid    = "AllowSageMakerAccess"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },

      # Allow CI/CD roles
      {
        Sid    = "AllowCICDRoles"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSageMakerDecrypt"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}



# --------------------------------------------------------------------------------------------
# Sagemaker Domain IAM permissions
# --------------------------------------------------------------------------------------------
module "sagemaker_domain_execution_role" {
  source  = "./submodules/iam"
  kms_arn = aws_kms_key.sagemaker_efs_kms_key.arn
}


# --------------------------------------------------------------------------------------------
# Sagemaker VPC module
# --------------------------------------------------------------------------------------------
module "sagemaker_domain_vpc" {
  source               = "./submodules/vpc"
  private_subnet_cidrs = local.vpc.private_subnet_cidrs
  azs                  = local.vpc.availability_zones
}


# --------------------------------------------------------------------------------------------
# Auto-shutdown idle notebooks (common for cost control in a domain used for development)
# --------------------------------------------------------------------------------------------
module "auto_shutdown_s3_upload" {
  source  = "./submodules/s3_notebook_auto_shutdown"
  kms_arn = aws_kms_key.sagemaker_efs_kms_key.arn
}

resource "aws_sagemaker_studio_lifecycle_config" "auto_shutdown" {
  studio_lifecycle_config_name     = "auto-shutdown"
  studio_lifecycle_config_app_type = "JupyterServer"
  studio_lifecycle_config_content  = base64encode(templatefile("${path.module}/assets/auto_shutdown_template/autoshutdown-script.sh", { tar_file_bucket = module.auto_shutdown_s3_upload.tar_file_bucket, tar_file_id = module.auto_shutdown_s3_upload.tar_file_id }))
}


# --------------------------------------------------------------------------------------------
# Sagemaker Domain
# --------------------------------------------------------------------------------------------
resource "aws_sagemaker_domain" "sagemaker_domain" {
  domain_name = var.domain_name
  auth_mode   = var.auth_mode
  vpc_id      = module.sagemaker_domain_vpc.vpc_id
  subnet_ids  = module.sagemaker_domain_vpc.subnet_ids

  default_user_settings {
    execution_role = module.sagemaker_domain_execution_role.default_execution_role

    jupyter_server_app_settings {
      default_resource_spec {
        lifecycle_config_arn = aws_sagemaker_studio_lifecycle_config.auto_shutdown.arn
        sagemaker_image_arn = local.sagemaker_image_arn
      }
      lifecycle_config_arns = [aws_sagemaker_studio_lifecycle_config.auto_shutdown.arn]
    }
  }
  

  domain_settings {
    security_group_ids = [module.sagemaker_domain_vpc.security_group_id]
  }

  kms_key_id = aws_kms_key.sagemaker_efs_kms_key.arn

  app_network_access_type = var.app_network_access_type

  retention_policy {
    home_efs_file_system = var.efs_retention_policy
  }
}


# --------------------------------------------------------------------------------------------
# Sagemaker Authentication: IAM / SSO
# --------------------------------------------------------------------------------------------
resource "aws_sagemaker_user_profile" "default_user" {
  domain_id         = aws_sagemaker_domain.sagemaker_domain.id
  user_profile_name = "ml-engineers"

  user_settings {
    execution_role  = module.sagemaker_domain_execution_role.default_execution_role
    security_groups = [module.sagemaker_domain_vpc.security_group_id]
  }
}


# resource "aws_sagemaker_user_profile" "domain_user_sso" {
#   domain_id         = aws_sagemaker_domain.this.id
#   user_profile_name = "my-sso-group-profile"

#   single_sign_on_user_identifier = var.sso_group_identifier
#   single_sign_on_user_value      = var.sso_group_value

#   user_settings {
#     execution_role  = aws_iam_role.domain_execution_role.arn
#     security_groups = [module.sagemaker_domain_vpc.security_group_id]
#   }
# }



# --------------------------------------------------------------------------------------------
# Sagemaker Project
# --------------------------------------------------------------------------------------------
# module "sagemaker_template_s3_upload" {
#   source  = "./submodules/s3_sagemaker_template"
#   kms_arn = aws_kms_key.sagemaker_efs_kms_key.arn
# }

resource "aws_servicecatalog_portfolio" "sagemaker_portfolio" {
  name          = "SageMaker MLOps Portfolio"
  description   = "Portfolio for SageMaker MLOps Project"
  provider_name = "DataScienceTeam"
}

resource "aws_servicecatalog_product" "catalog_product" {
  name        = "SageMakerProject"
  owner       = "DataScienceTeam"
  description = "Custom MLOps pipeline template without Lambda"
  type        = "CLOUD_FORMATION_TEMPLATE"

  provisioning_artifact_parameters {
    name         = "v1.4"
    description  = "Version 1 of MLOps pipeline"
    type         = "CLOUD_FORMATION_TEMPLATE"
    template_url = module.auto_shutdown_s3_upload.s3_object_url
  }

  tags = {
    "sagemaker:studio-visibility" = "true"
  }
}

resource "aws_servicecatalog_product_portfolio_association" "product_portfolio" {
  portfolio_id = aws_servicecatalog_portfolio.sagemaker_portfolio.id
  product_id   = aws_servicecatalog_product.catalog_product.id
}

# Add porfolio constraints
resource "aws_servicecatalog_constraint" "example" {
  description  = "AmazonSageMakerServiceCatalogProductsLaunchRole"
  portfolio_id = aws_servicecatalog_portfolio.sagemaker_portfolio.id
  product_id   = aws_servicecatalog_product.catalog_product.id
  type         = "LAUNCH"

  parameters = jsonencode({
    "RoleArn" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/AmazonSageMakerServiceCatalogProductsLaunchRole"
  })
}

# Add porfolio Access
resource "aws_servicecatalog_principal_portfolio_association" "example" {
  portfolio_id  = aws_servicecatalog_portfolio.sagemaker_portfolio.id
  principal_arn = module.sagemaker_domain_execution_role.default_execution_role
}

# # Create the SageMaker Project
# resource "aws_sagemaker_project" "catalog_project" {
#   project_name = "SageMaker-mlops-project"

#   service_catalog_provisioning_details {
#     product_id               = aws_servicecatalog_product.catalog_product.id
#     # # To-do: Automate
#     # provisioning_artifact_id = "port-oifsm5ux43vcm"
#   }

#   tags = {
#     Environment = "Test"
#     Project     = "MLOps"
#   }
# }