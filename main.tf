provider "aws" {
  region = "eu-central-1" // -> Frankfurt
}

resource "aws_iam_role" "tf_aws_exercise_role" {
  name               = "tfExerciseRole"
  description        = "Role that allowed to be assumed by AWS Lambda, which will be taking all actions."
  tags = {
      owner = "tfExerciseBoss"
  }
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "basic-exec-role" {
  role       = aws_iam_role.tf_aws_exercise_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_lambda_access" {
  statement {
    effect    = "Allow"
    resources = ["arn:aws:s3:::tf-aws-bucket/*"]
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
  }
}

resource "aws_iam_policy" "s3_lambda_access" {
  name   = "s3_lambda_access"
  path   = "/"
  policy = data.aws_iam_policy_document.s3_lambda_access.json
}

resource "aws_iam_role_policy_attachment" "s3_lambda_access" {
  role       = aws_iam_role.tf_aws_exercise_role.name
  policy_arn = aws_iam_policy.s3_lambda_access.id
}

data "aws_iam_policy_document" "sqs_lambda_access" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:eu-central-1:546454927816:tf-aws-queue  "]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:SendMessage",
    ]
  }
}

resource "aws_iam_policy" "sqs_lambda_access" {
  name   = "sqs_lambda_access"
  policy = data.aws_iam_policy_document.sqs_lambda_access.json
}

resource "aws_iam_role_policy_attachment" "sqs_lambda_access" {
  policy_arn = aws_iam_policy.sqs_lambda_access.id
  role       = aws_iam_role.tf_aws_exercise_role.name
}

resource "aws_lambda_function" "lambda_function" {
  role             = aws_iam_role.tf_aws_exercise_role.arn
  handler          = "lambda.handler"
  runtime          = "python3.6"
  filename         = "lambda.zip"
  function_name    = "tf_aws_function"
  source_code_hash = base64sha256(filebase64("lambda.zip"))
}

resource "aws_lambda_permission" "allow_cloudwatch_events_call" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_collect_event.arn
}

resource "aws_sqs_queue" "message_queue" {
  name                      = "tf-aws-queue"
  delay_seconds             = 15
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

}

resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.message_queue.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${aws_sqs_queue.message_queue.arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_s3_bucket.tf_aws_bucket.arn}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_cloudwatch_event_rule" "scheduled_collect_event" {
  name                = "scheduled_collect_event"
  description         = "Periodic call to AWS Lambda function"
  schedule_expression = "cron(0/2 * * * ? *)"
}

resource "aws_cloudwatch_event_target" "lambda_target_details" {
  arn       = aws_lambda_function.lambda_function.arn
  input     = "{\"org_name\":\"github\", \"target_bucket\":\"tf-aws-bucket\"}"
  rule      = aws_cloudwatch_event_rule.scheduled_collect_event.name
  target_id = "AWSLambdaFunc"
}

resource "aws_s3_bucket" "tf_aws_bucket" {
  bucket = "tf-aws-bucket"
  tags = {
    Name        = "My bucket for Cisco Prague interview"
    Environment = "Dev"
  }
  force_destroz = "true"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.tf_aws_bucket.id

  queue {
    queue_arn     = aws_sqs_queue.message_queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".gz"
  }
}