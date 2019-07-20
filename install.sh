#!/bin/bash

################################################################################
## @author: Maycon Brito
## @email: mayconfsbrito@gmail.com
################################################################################

EC2_AMI_IMAGE="ami-024a64a6685d05041" # Ubuntu Server 18.04
EC2_SG_NAME="sg-web"
EC2_KEYPAIR_NAME="automation-key"
EC2_WEBAPP_JAR_FILE="acesso.jar"
RDS_DB_USER="postgres"
RDS_DB_PASS="passwdexemplo"
RDS_DB_PORT=5432
RDS_DB_NAME="acessos"
RDS_DB_SCRIPT_FILE_NAME="acesso_init.sql"
RDS_DB_ENGINE="postgres"
RDS_DB_STORAGE=20
RDS_DB_INSTANCE_CLASS="db.t2.small"
RDS_SG_NAME="rds-subnet-group"
ZONE_1="use1-az3"
ZONE_2="use1-az4"


printf "[EC2] Checking KeyPair..."
if [ -f "${EC2_KEYPAIR_NAME}.pem" ]; then
    printf "already exists... "
   
else
    printf " creating... "

    KEYPAIR=$(aws ec2 describe-key-pairs --filters "Name=key-name,Values=${EC2_KEYPAIR_NAME}" --output text)
    if [ -z "$KEYPAIR" ] || [ "$KEYPAIR" == " " ]; then
        aws ec2 create-key-pair --key-name ${EC2_KEYPAIR_NAME} --query "KeyMaterial" --output text > ${EC2_KEYPAIR_NAME}.pem
        chmod 400 ${EC2_KEYPAIR_NAME}.pem
    else
        printf "\nError! Key ${EC2_KEYPAIR_NAME} already exists in EC2.\n\n"
        exit
    fi
fi
echo "OK"

#Create or Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr-block,Values=10.0.0.0/16" "Name=state,Values=available" "Name=is-default,Values=false" --query 'Vpcs[0].VpcId' --output text)
if [ $VPC_ID == "None" ]
    then
        VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)
fi
echo "[EC2] VPC ID: " $VPC_ID

#Enable DNS Hostname and Support to VPC
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support "{\"Value\":true}"

#Create or Get Subnet ID
SUBNET_ID_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}"  "Name=availability-zone-id,Values=${ZONE_1}" --query 'Subnets[0].SubnetId' --output text)
if [ $SUBNET_ID_1 == "None" ]
    then
        SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --availability-zone-id ${ZONE_1} --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text)
fi
echo "[EC2] Subnet ID [$ZONE_1]: "$SUBNET_ID_1
SUBNET_ID_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}"  "Name=availability-zone-id,Values=${ZONE_2}" --query 'Subnets[0].SubnetId' --output text)
if [ $SUBNET_ID_2 == "None" ]
    then
        SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id ${VPC_ID} --availability-zone-id ${ZONE_2} --cidr-block 10.0.2.0/24 --query 'Subnet.SubnetId' --output text)
fi
echo "[EC2] Subnet ID [$ZONE_2]: "$SUBNET_ID_2

# RDS Instance
printf "[RDS] Checking RDS instance..."
RDS_INSTANCE=$(aws rds describe-db-instances | jq '.DBInstances[] | select(.DBInstanceIdentifier | contains("'${RDS_DB_NAME}'"))')
if [ -z "$RDS_INSTANCE" ]
    then
        printf "\n[RDS] Creating instance..."
        aws rds delete-db-subnet-group --db-subnet-group-name "${RDS_SG_NAME}" 2> /dev/null
        aws rds create-db-subnet-group --db-subnet-group-name "${RDS_SG_NAME}" --db-subnet-group-description "automation" --subnet-ids $SUBNET_ID_1 $SUBNET_ID_2 > /dev/null

        RDS_INSTANCE=$(aws rds create-db-instance \
            --db-instance-identifier postgres-${RDS_DB_NAME} \
            --allocated-storage ${RDS_DB_STORAGE} \
            --db-instance-class ${RDS_DB_INSTANCE_CLASS} \
            --engine ${RDS_DB_ENGINE} \
            --master-username ${RDS_DB_USER} \
            --master-user-password ${RDS_DB_PASS} \
            --db-subnet-group-name ${RDS_SG_NAME})
        echo ${RDS_INSTANCE} >> install.log 
fi
#echo $RDS_INSTANCE | jq
RDS_INSTANCE_ID=$(echo $RDS_INSTANCE | jq '.Instances[0].InstanceId')
echo "OK"

#Creating (and Attaching) or Get Internet Gateway
EC2_INTERNET_GATEWAY_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=${VPC_ID} --query 'InternetGateways[0].InternetGatewayId' --output text)
if [ $EC2_INTERNET_GATEWAY_ID == "None" ]
    then
        printf "[EC2] Creating Internet Gateway..."
        EC2_INTERNET_GATEWAY_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
        echo "OK"
        printf "[EC2] Attach Internet Gateway..."
        aws ec2 attach-internet-gateway --internet-gateway-id ${EC2_INTERNET_GATEWAY_ID} --vpc-id ${VPC_ID}
        echo "OK"
fi
echo "[EC2] Internet Gateway ID: ${EC2_INTERNET_GATEWAY_ID}"

#Route Table
EC2_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id ${VPC_ID} --query 'RouteTable.RouteTableId' --output text)
echo "[EC2] Route Table ID: ${EC2_ROUTE_TABLE_ID}"

#Route Table Associations
printf "[EC2] Checking Route Tables Associations..."
ASSOCIATED_RTB_1=$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=${SUBNET_ID_1} --query 'RouteTables[0].RouteTableId' --output text)
if [ $ASSOCIATED_RTB_1 == "None" ]
    then
    printf "\n[EC2] Associate Route Table to Subnet 1..."
    aws ec2 associate-route-table --route-table-id ${EC2_ROUTE_TABLE_ID} --subnet-id ${SUBNET_ID_1} > /dev/null
fi
ASSOCIATED_RTB_2=$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=${SUBNET_ID_2} --query 'RouteTables[0].RouteTableId' --output text)
if [ $ASSOCIATED_RTB_2 == "None" ]
    then
    printf "\n[EC2] Associate Route Table to Subnet 2..."
    aws ec2 associate-route-table --route-table-id ${EC2_ROUTE_TABLE_ID} --subnet-id ${SUBNET_ID_2} > /dev/null
fi

#Routes
printf "\n[EC2] Create Route..."
aws ec2 create-route --route-table-id ${EC2_ROUTE_TABLE_ID} --destination-cidr-block 0.0.0.0/0 --gateway-id ${EC2_INTERNET_GATEWAY_ID} > /dev/null
printf "OK\n"

#Create or Get SG ID
SG_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text)
if [ $SG_ID == "None" ]
    then
        SG_ID=$(aws ec2 create-security-group --group-name ${EC2_SG_NAME} --vpc-id ${VPC_ID} --description "Security Group of Automation EC2-RDS" --query 'GroupId' --output text)
fi
echo "[EC2] Security Group ID: " $SG_ID

# Security Group Firewall
echo "[EC2] Authorizing HTTP port"
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2> /dev/null
echo "[EC2] Authorizing SSH port"
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 2> /dev/null

# Create EC2 Instance
echo "[EC2] Creating Instance..."
EC2_INSTANCE=$(aws ec2 run-instances \
    --security-group-ids ${SG_ID} \
    --subnet-id ${SUBNET_ID_1} \
    --no-dry-run \
    --image-id ${EC2_AMI_IMAGE} \
    --count 1 \
    --instance-type t2.micro \
    --key-name ${EC2_KEYPAIR_NAME} \
    --associate-public-ip-address)

EC2_INSTANCE_ID=$(echo $EC2_INSTANCE | jq -r '.Instances[0].InstanceId')
echo "[EC2] Instance ID: " ${EC2_INSTANCE_ID}
echo ${EC2_INSTANCE} >> install.log

# EC2 DNS
printf "[EC2] Waiting Public DNS..."
end=$((SECONDS+60))
STR_ECS_ENDPOINT="aws ec2 describe-instances --filters Name=instance-id,Values=${EC2_INSTANCE_ID} --query 'Reservations[0].Instances[0].PublicDnsName' --output text"
EC2_DNS=$(eval $STR_ECS_ENDPOINT)
while [[ $EC2_DNS != *"amazonaws.com"* ]] && [[ $SECONDS -lt $end ]]; do
    sleep 10s
    EC2_DNS=$(eval $STR_ECS_ENDPOINT)
done
echo "OK"
echo "[EC2] Public DNS Name: " $EC2_DNS

# EC2 Docker
echo "[EC2] Installing Docker..."
#echo "\"ssh -o StrictHostKeyChecking=no -i ${EC2_KEYPAIR_NAME}.pem ubuntu@${EC2_DNS}\""
ssh -o StrictHostKeyChecking=no -i ${EC2_KEYPAIR_NAME}.pem ubuntu@${EC2_DNS} /bin/bash << EOF 
    curl -fsSL https://get.docker.com -o get-docker.sh > /dev/null
    sudo sh get-docker.sh
    sudo usermod -aG docker ubuntu
EOF

printf "\n\n[EC2] Copying webapp..."
scp -o StrictHostKeyChecking=no -i ${EC2_KEYPAIR_NAME}.pem ${EC2_WEBAPP_JAR_FILE} ubuntu@${EC2_DNS}:/home/ubuntu/
echo "OK"

#RDS Endpoint
printf "[RDS] Waiting Endpoint..."
end=$((SECONDS+360))
STR_RDS_ENDPOINT="aws rds describe-db-instances | jq '.DBInstances[] | select(.DBInstanceIdentifier | contains(\"${RDS_DB_NAME}\"))' | jq -r '.Endpoint.Address'"
RDS_ENDPOINT=$(eval $STR_RDS_ENDPOINT)
while [[ ${RDS_ENDPOINT} != *"amazonaws.com"* ]] && [[ $SECONDS -lt $end ]]; do
  sleep 10s
  RDS_ENDPOINT=$(eval $STR_RDS_ENDPOINT)
done
echo "OK"
echo "[RDS] Endpoint: " ${RDS_ENDPOINT}

##Testa a conexão com o banco de dados RDS
##ssh -i -o StrictHostKeyChecking=no "${EC2_KEYPAIR_NAME}.pem" ubuntu@${EC2_PUBLIC_DNS} 

printf "\n[EC2] Running webapp through java container...\n"
echo "[EC2] ssh -o StrictHostKeyChecking=no -i ${EC2_KEYPAIR_NAME}.pem ubuntu@${EC2_DNS}"
ssh -o StrictHostKeyChecking=no -i ${EC2_KEYPAIR_NAME}.pem ubuntu@${EC2_DNS} /bin/bash << EOF
    docker run -p 80:9095 -v /home/ubuntu/:/usr/src/ -w /usr/src/ \
        java:8 \
        java \
        -Dspring.datasource.url=jdbc:postgresql://${RDS_ENDPOINT}:${RDS_DB_PORT}/${RDS_DB_NAME} \
        -Dspring.datasource.username=${RDS_DB_USER} \
        -Dspring.datasource.password=${RDS_DB_PASS} \
        -jar ${EC2_WEBAPP_JAR_FILE} -d
EOF
    # -Dspring.datasource.url=jdbc:postgresql://${RDS_ENDPOINT}:${RDS_PORT}/${RDS_DB_PORT} \
    # -Dspring.datasource.username=${RDS_USER} \
    # -Dspring.datasource.password=${RDS_PASS} \

#Deletes the instance and vpc
# aws ec2 terminate-instances --instance-ids ${EC2_INSTANCE_ID}
# aws ec2 delete-vpc --vpc-id ${VPC_ID}