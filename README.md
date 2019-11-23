# Terraform project on AWS Cloud

![architecture overview](arch.png "Architecture")

AWS Terraform Project with:
- Lambda serverless implementation (Python)
- S3 bucket for storage
- SQS queue for notifications
- CW scheduling to trigger Lambda

## Steps to deploy with terraform

### Step 1: Package the code

Since we use terraform to deploy the Lambda function, we need a way to package and deliver the code that will be called when a request comes in. This is achieved by wrapping the python file in a zip and specifying it in the terraform code section `aws_lambda_function`. The simplest way to achieve this is by calling the zip program via the CLI:

```bash
$ zip -r lambda.zip lambda.py
```

A small caveat I discovered with this approach, since the summer when I first ran this code. The vendored botocore python module is being deprecated, so there was a warning on the AWS Lambda console output:

```
...
/var/runtime/botocore/vendored/requests/api.py:67: DeprecationWarning: You are using the get() function from 'botocore.vendored.requests'.  This is not a public API in botocore and will be removed in the future. Additionally, this version of requests is out of date.  We recommend you install the requests package, 'import requests' directly, and use the requests.get() function instead.
  DeprecationWarning
...
```

To fix this error I had to package the source code together with the `requests` python module, so the AWS Lambda can call the function I use to fetch the data from the REST API. To do this I folled a how-to on AWS:

```bash
# Install the required package in a subdir
  $ pip install --target ./package requests
# Zip the contents of this new subdir
  $ cd package
  $ zip -r9 ${OLDPWD}/function.zip .
# Finally add to the ZIP the python source code
  $ cd $OLDPWD
  $ zip -g function.zip function.py
```

### Step 2: Deploy with Terraform

Now we have a ZIP that contains any necessary Python package we use plus the source code, so it is ready to be used by Terraform. In order to deploy the whole project to AWS, use the below commands

```shell
$ cd dir_with_main.tf
$ terraform init
$ terraform apply
```
