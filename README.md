# aws-key-rotation-scripts

**Bash scripts for automating AWS EC2 and IAM key rotation.**

These bash scripts are used to automate key rotation for AWS. They are the companion code to this blog article:
[Strengthen Your AWS Security by Protecting App Credentials and Automating EC2 and IAM Key Rotation]
(http://www.randomant.net/strengthen-your-aws-security-by-protecting-app-credentials-and-automating-ec2-and-iam-key-rotation)


<b>rotate-ec2-key.sh</b> is a bash script that rotates EC2 SSH keys. It follows the process below to rotate the key:
1. Create a new key pair using ssh-keygen (not using AWS’s key pair functionality.)
2. Add the public key portion of the SSH key pair to the ~./ssh/authorized_keys file for the root/admin account on the EC2 instance.
3. Test by logging into the instance with the new key.
4. If everything works, remove the original key.
5. Re-test to confirm it still works.
6. Create/update a tag called “EC2KeyName” that contains the name of the new SSH key
