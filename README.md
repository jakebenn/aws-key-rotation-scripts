# aws-key-rotation-scripts

**Bash scripts for automating AWS EC2 and IAM key rotation.**

These bash scripts are used to automate key rotation for AWS. They are the companion code to this blog article:
[Strengthen Your AWS Security by Protecting App Credentials and Automating EC2 and IAM Key Rotation]
(http://www.randomant.net/strengthen-your-aws-security-by-protecting-app-credentials-and-automating-ec2-and-iam-key-rotation)


<b>rotate-ec2-key.sh</b> is a bash script that rotates EC2 SSH keys. It is has been tested with Ubuntu, Amazon Linux and CoreOS.
CoreOS does not support EC2 key rotation if you are using [cloud-config](https://coreos.com/os/docs/latest/cloud-config.html).
It only works if you use CoreOS's new initialization/provisioning system
[Ignition](https://coreos.com/ignition/docs/0.2.1/what-is-ignition.html). See the blog article referenced above for more details
on why Ignition is required.

The script follows the process below to rotate the key:

1. Create a new key pair using ssh-keygen (not using AWS’s key pair functionality.)
2. Add the public key portion of the SSH key pair to the `~./ssh/authorized_keys` file for the root/admin account on the EC2 instance.
3. Test by logging into the instance with the new key.
4. For CoreOS instances: If everything works, remove the original key by replacing the SSH key in
the `~/.ssh/authorized_keys.d/coreos-ignition` file and run update-ssh-key to enable the change. For other
distros: If everything works, remove the original key.
5. Re-test to confirm it still works.
6. Create/update a tag called “EC2KeyName” that contains the name of the new SSH key


```usage: rotate-ec2-key.sh [options...]
options:
 -s --ssh-key-file  Path to EC2 private ssh key file for the key to be replaced. Required.
 -h --host          IP address or DNS name for the EC2 instance. Required.
 -a --aws-key-file  The file for the .csv access key file for an AWS administrator. Optional. The AWS administrator
                    must have the rights to create tags for EC2 instances. The script expects the .csv format
                    used when you dowload the key from IAM in the AWS console. If you don't specify a key file,
                    the default credentials in ~/.aws/credentials will be used.
 -u --user          Root/admin user for the EC2 instance. Optional. The default value is 'core' (for the CoreOS distro).
 -j --json          A file to send JSON output to. Optional.
    --help          Prints this help message
 ```
