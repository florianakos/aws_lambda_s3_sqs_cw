
######################## Configure the provider ################################

provider "aws" {
  region = "eu-central-1"  // -> Frankfurt
}

######################## Create Lambda Function resource #######################

resource "aws_lambda_function" "lambda_function" {
  role             = "${aws_iam_role.cisco_prague_exercise_role.arn}"
  handler          = "lambda.handler"  
  runtime          = "python3.6"
  filename         = "lambda.zip" 
  function_name    = "cisco_prague_function"
  source_code_hash = "${base64sha256(filebase64("lambda.zip"))}"
}

resource "aws_lambda_permission" "allow_cloudwatch_events_call" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.lambda_function.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.scheduled_collect_event.arn}"
}

######################## Create CloudWatch Event Rule ##########################

resource "aws_cloudwatch_event_rule" "scheduled_collect_event" {
    name = "scheduled_collect_event"
    description = "scheduled_collect_event"
    schedule_expression = "cron(0/2 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target_details" {
  arn       = "${aws_lambda_function.lambda_function.arn}"
  input     = "{\"org_name\":\"github\", \"target_bucket\":\"cisco-prague\"}"
  rule      = "${aws_cloudwatch_event_rule.scheduled_collect_event.name}"
  target_id = "AWSLambdaFunc"
}

######################## Create S3 bucket resource ##############################

resource "aws_s3_bucket" "cisco_prague_bucket" {
  bucket = "cisco-prague"
  tags   = {
    Name        = "My bucket for Cisco Prague interview"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.cisco_prague_bucket.id}"
  queue {
    queue_arn     = "${aws_sqs_queue.message_queue.arn}"
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".gz"
  }
}

######################## Create SQS queue resource ##############################

resource "aws_sqs_queue" "message_queue" {
  name                      = "cisco-prague-queue"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:*:*:cisco-prague-queue",
      "Condition": {
        "ArnEquals": { 
          "aws:SourceArn": "${aws_s3_bucket.cisco_prague_bucket.arn}"
        }
      }
    }
  ]
}
POLICY
}

####################### Define IAM Role ################################

resource "aws_iam_role" "cisco_prague_exercise_role" {
    name = "check_file_lambda"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "basic-exec-role" {
    role       = "${aws_iam_role.cisco_prague_exercise_role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#################### Define S3 policy for Lambda #######################

data "aws_iam_policy_document" "s3_lambda_access" {
    statement {
        effect    = "Allow"
        resources = ["arn:aws:s3:::cisco-prague/*"]
        actions   = [
                      "s3:GetObject",
                      "s3:PutObject",
                      "s3:ListBucket",
        ]
        
    }
}

resource "aws_iam_policy" "s3_lambda_access" {
    name  = "s3_lambda_access"
    path  = "/"
    policy = "${data.aws_iam_policy_document.s3_lambda_access.json}"
}

resource "aws_iam_role_policy_attachment" "s3_lambda_access" {
    role       = "${aws_iam_role.cisco_prague_exercise_role.name}"
    policy_arn = "${aws_iam_policy.s3_lambda_access.arn}"
}

#################### Define SQS policy for Lambda ######################

data "aws_iam_policy_document" "sqs_lambda_access" {
    statement {
      sid       = "AllowSQSPermissions"
      effect    = "Allow"
      resources = ["arn:aws:sqs:eu-central-1:546454927816:cisco-prague-queue  "]
      actions   = [
                    "sqs:DeleteMessage",
                    "sqs:GetQueueUrl",
                    "sqs:ReceiveMessage",
                    "sqs:SendMessage",
      ]
    }
}

resource "aws_iam_policy" "sqs_lambda_access" {
  name = "sqs_lambda_access"
  policy = "${data.aws_iam_policy_document.sqs_lambda_access.json}"
}

resource "aws_iam_role_policy_attachment" "sqs_lambda_access" {
  policy_arn = "${aws_iam_policy.sqs_lambda_access.arn}"
  role = "${aws_iam_role.cisco_prague_exercise_role.name}"
}

##################################################################################