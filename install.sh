#!/bin/bash

################################################################################
## @author: Maycon Brito
## @email: mayconfsbrito@gmail.com
################################################################################

KEY_NAME="teste"
EC2_AMI_IMAGE="ami-024a64a6685d05041" # Ubuntu Server 18.04
EC2_SG_NAME="sg-web"
EC2_KEYPAIR_NAME="automation-key"
RDS_DB_USER="postgres"
RDS_DB_PASS="passwdexemplo"
RDS_DB_PORT=5432
RDS_DB_NAME="acessos"
RDS_DB_ENGINE="postgres"
RDS_DB_STORAGE=20
RDS_DB_INSTANCE_CLASS="db.t2.small"
RDS_SG_NAME="rds-subnet-group"
ZONE_1="use1-az3"
ZONE_2="use1-az4"

#Create or Get VPC ID
#VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr-block,Values=10.0.0.0/16" "Name=state,Values=available" "Name=is-default,Values=false" --query 'Vpcs[0].VpcId' --output text)
#if [ $VPC_ID == "None" ]
#    then
#        VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
#fi
#echo "VPC ID: " $VPC_ID
#
##Enable DNS Hostname to VPC
#aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames "{\"Value\":true}"
#
##Create or Get SG ID
#SG_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text)
#if [ $SG_ID == "None" ]
#    then
#        SG_ID=$(aws ec2 create-security-group --group-name ${EC2_SG_NAME} --vpc-id ${VPC_ID} --description "SG of HTTP" --query 'GroupId' --output text)
#fi
#echo "Security Group ID: " $SG_ID
#
#echo "[EC2] Authorizing HTTP port"
#aws ec2 authorize-security-group-ingress \
#    --group-id $SG_ID \
#    --protocol tcp \
#    --port 80 \
#    --cidr 0.0.0.0/0 2> /dev/null
#
##Create or Get Subnet ID
#SUBNET_ID_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}"  "Name=availability-zone-id,Values=${ZONE_1}" --query 'Subnets[0].SubnetId' --output text)
#if [ $SUBNET_ID_1 == "None" ]
#    then
#        SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --availability-zone-id ${ZONE_1} --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text)
#fi
#echo "Subnet ID [$ZONE_1]: "$SUBNET_ID_1
#SUBNET_ID_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}"  "Name=availability-zone-id,Values=${ZONE_2}" --query 'Subnets[0].SubnetId' --output text)
#if [ $SUBNET_ID_2 == "None" ]
#    then
#        SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --availability-zone-id ${ZONE_2} --cidr-block 10.0.2.0/24 --query 'Subnet.SubnetId' --output text)
#fi
#echo "Subnet ID [$ZONE_2]: "$SUBNET_ID_2
#
#echo "[EC2] Creating Instance..."
#EC2_INSTANCE=$(aws ec2 run-instances \
#    --security-group-ids ${SG_ID} \
#    --subnet-id ${SUBNET_ID_1} \
#    --no-dry-run \
#    --image-id ${EC2_AMI_IMAGE} \
#    --count 1 \
#    --instance-type t2.micro \
#    --associate-public-ip-address)
#
#EC2_INSTANCE_ID=$(echo $EC2_INSTANCE | jq -r '.Instances[0].InstanceId')
#echo "[EC2] Instance ID: " ${EC2_INSTANCE_ID}
#echo ${EC2_INSTANCE}

#Create DB Security Group
#aws rds create-db-subnet-group --db-subnet-group-name "rds-subnet-group" --db-subnet-group-description "automation" --subnet-ids $SUBNET_ID_1 $SUBNET_ID_2 2> /dev/null
#
#echo "[RDS] Creating instance"
#RDS_INSTANCE=$(aws rds create-db-instance \
#    --db-instance-identifier postgres-${RDS_DB_NAME} \
#    --allocated-storage ${RDS_DB_STORAGE} \
#    --db-instance-class ${RDS_DB_INSTANCE_CLASS} \
#    --engine ${RDS_DB_ENGINE} \
#    --master-username ${RDS_DB_USER} \
#    --master-user-password ${RDS_DB_PASS} \
#    --db-subnet-group-name ${RDS_SG_NAME})
#

printf "[EC2] Waiting Public DNS..."
end=$((SECONDS+120))
STR_ECS_ENDPOINT="aws ec2 describe-instances --filters Name=instance-id,Values=i-06e14ae63fe55dd36  --query 'Reservations[0].Instances[0].PublicDnsName' --output text"
EC2_DNS=$(eval $STR_ECS_ENDPOINT)
while [[ $EC2_DNS != *"amazonaws.com"* ]] && [[ $SECONDS -lt $end ]]; do
    sleep 10s
    EC2_DNS=$(eval $STR_ECS_ENDPOINT)
done
echo "OK"
echo "[EC2] Public DNS Name: " $EC2_DNS

printf "[EC2] Checking KeyPair..."
KEYPAIR=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=automation-key" --output text)
if [ ! -z "$KEYPAIR" -a "$KEYPAIR" != " " ]; then
    aws ec2 create-key-pair --key-name ${EC2_KEYPAIR_NAME}
fi
echo "OK"


echo "[EC2] Installing Docker"
ssh -i "${KEY_NAME}.pem" ubuntu@${EC2_DNS} sudo apt-get update && sudo apt search docker && sudo apt-get install docker docker-compose

#echo "[EC2] Copying webapp"
#ssh -i "${KEY_NAME}.pem" ubuntu@${EC2_PUBLIC_DNS} mkdir -p /home/ubuntu/webapp/
#scp -i "${KEY_NAME}.pem" acesso.jar ubuntu@${EC2_PUBLIC_DNS}:/home/ubuntu/webapp/

#Testa a conexão com o banco de dados RDS
#ssh -i "${KEY_NAME}.pem" ubuntu@${EC2_PUBLIC_DNS} 