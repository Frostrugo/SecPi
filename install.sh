#!/bin/bash

echo "  _________            __________.__                    
 /   _____/ ____   ____\______   \__|                   
 \_____  \_/ __ \_/ ___\|     ___/  |                   
 /        \  ___/\  \___|    |   |  |                   
/_______  /\___  >\___  >____|   |__|                   
        \/     \/     \/                                
.___                 __         .__  .__                
|   | ____   _______/  |______  |  | |  |   ___________ 
|   |/    \ /  ___/\   __\__  \ |  | |  | _/ __ \_  __ \\
|   |   |  \\\\___ \  |  |  / __ \|  |_|  |_\  ___/|  | \/
|___|___|  /____  > |__| (____  /____/____/\___  >__|   
         \/     \/            \/               \/       "


SECPI_PATH="/opt/secpi"
LOG_PATH="/var/log/secpi"
TMP_PATH="/var/tmp/secpi"
CERT_PATH="$SECPI_PATH/certs"

# creates a folder and sets permissions to given user and group
function create_folder(){
	if [ -d $1 ];
	then
		echo "$1 exists!"
		return 0
	fi
	mkdir $1
	if [ $? -ne 0 ];
	then
		echo "Couldn't create $1"
		exit 3
	else
		echo "Created $1"
	fi

	chown $2:$3 $1
	if [ $? -ne 0 ];
	then
		echo "Couldn't change user and group of $1 to the specified user and group ($2, $3)!"
		exit 4
	else
		echo "Changed user and group of $1 to $2 and $3"
	fi
}
# generates and signs a certificate with the passed name
# second parameter is extension (client/server)
function gen_and_sign_cert(){
	# generate key
	openssl genrsa -out $CERT_PATH/$1.key.pem 2048
	# generate csr
	openssl req -config $CERT_PATH/ca/openssl.cnf -new -key $CERT_PATH/$1.key.pem -out $CERT_PATH/$1.req.pem -outform PEM -subj /CN=$1/ -nodes
	# sign cert
	openssl ca -config $CERT_PATH/ca/openssl.cnf -in $CERT_PATH/$1.req.pem -out $CERT_PATH/$1.cert.pem -notext -batch -extensions $2
}


# got at least two arguments
# --update <worker|manager|webinterface|all>
# -u <worker|manager|webinterface|all>
if [ $# -ge 2 ]
then
	if [ $1 = "-u" ] || [ $1 = "--update" ]
	then
		# copy tools folder
		find tools/ -name '*.py' | cpio -updm $SECPI_PATH
		if [ $2 = "worker" ] || [ $2 = "all" ]
		then
			/etc/init.d/secpi-worker stop
			find worker/ -name '*.py' | cpio -updm $SECPI_PATH
			chmod 755 $SECPI_PATH/worker/worker.py
			/etc/init.d/secpi-worker start
		fi
		
		if [ $2 = "manager" ] || [ $2 = "all" ]
		then
			/etc/init.d/secpi-manager stop
			find manager/ -name '*.py' | cpio -updm $SECPI_PATH
			chmod 755 $SECPI_PATH/manager/manager.py
			/etc/init.d/secpi-manager start
		fi
		
		if [ $2 = "webinterface" ] || [ $2 = "all" ]
		then
			/etc/init.d/secpi-webinterface stop
			find webinterface/ -name '*.py' | cpio -updm $SECPI_PATH
			chmod 755 $SECPI_PATH/webinterface/main.py
			/etc/init.d/secpi-webinterface start
		fi
		
		# only copy files in update mode
		exit 0
	fi
fi


echo "Please input the user which SecPi should use:"
read SECPI_USER

echo "Please input the group which SecPi should use:"
read SECPI_GROUP

echo "Select installation type:"
echo "[1] Complete installation (manager, webui, worker)"
echo "[2] Management installation (manager, webui)"
echo "[3] Worker installation (worker only)"
read INSTALL_TYPE

echo "Enter RabbitMQ Server IP"
read MQ_IP

echo "Enter RabbitMQ Server Port (default: 5671)"
read MQ_PORT

if [ "$MQ_PORT" = ""]
then
	MQ_PORT="5671"
fi

echo "Enter RabbitMQ User"
read MQ_USER

echo "Enter RabbitMQ Password"
read MQ_PWD

echo "Enter certificate authority domain (for rabbitmq and webserver, default: secpi.local)"
read CA_DOMAIN

if [ "$CA_DOMAIN" = ""]
then
	CA_DOMAIN="secpi.local"
fi

if [ $INSTALL_TYPE -eq 1 ] || [ $INSTALL_TYPE -eq 2 ]
then
	echo "Enter name for webserver certificate (excluding $CA_DOMAIN)"
	read WEB_CERT_NAME
	
	echo "Enter user for webinterface:"
	read WEB_USER
	
	echo "Enter password for webinterface:"
	read WEB_PWD
fi




################################################################################################
# create log folder
create_folder $LOG_PATH $SECPI_USER $SECPI_GROUP

################################################################################################
# create secpi folder
create_folder $SECPI_PATH $SECPI_USER $SECPI_GROUP

################################################################################################
# create run folder
# create_folder $SECPI_PATH/run $SECPI_USER $SECPI_GROUP

# create tmp folder
create_folder $TMP_PATH $SECPI_USER $SECPI_GROUP
create_folder $TMP_PATH/worker_data $SECPI_USER $SECPI_GROUP
create_folder $TMP_PATH/alarms $SECPI_USER $SECPI_GROUP



# generate certificates for rabbitmq
create_folder $CERT_PATH $SECPI_USER $SECPI_GROUP
create_folder $CERT_PATH/ca $SECPI_USER $SECPI_GROUP
create_folder $CERT_PATH/ca/private $SECPI_USER $SECPI_GROUP
create_folder $CERT_PATH/ca/crl $SECPI_USER $SECPI_GROUP
create_folder $CERT_PATH/ca/newcerts $SECPI_USER $SECPI_GROUP
touch $CERT_PATH/ca/index.txt
echo 1000 > $CERT_PATH/ca/serial

cp scripts/openssl.cnf $CERT_PATH/ca/

# generate ca cert
openssl req -config $CERT_PATH/ca/openssl.cnf -x509 -newkey rsa:2048 -days 365 -out $CERT_PATH/ca/cacert.pem -keyout $CERT_PATH/ca/private/cakey.pem -outform PEM -subj /CN=$CA_DOMAIN/ -nodes

# generate mq server certificate
gen_and_sign_cert mq-server.$CA_DOMAIN server

# add rabbitmq user and set permissions
rabbitmqctl add_user $MQ_USER $MQ_PWD
rabbitmqctl set_permissions $MQ_USER "secpi.*" "secpi.*" "secpi.*"

echo "Current SecPi folder: $PWD"
echo "Copying to $SECPI_PATH..."

# copy tools folder
cp -R tools/ $SECPI_PATH/
cp logging.conf $SECPI_PATH/

# manager or complete install
if [ $INSTALL_TYPE -eq 1 ] || [ $INSTALL_TYPE -eq 2 ]
then
	echo "Copying manager..."
	cp -R manager/ $SECPI_PATH/
	echo "Copying webinterface..."
	cp -R webinterface/ $SECPI_PATH/
	
	echo "Creating config..."
	
	sed -i "s/<ip>/$MQ_IP/" $SECPI_PATH/manager/config.json $SECPI_PATH/webinterface/config.json
	sed -i "s/<port>/$MQ_PORT/" $SECPI_PATH/manager/config.json $SECPI_PATH/webinterface/config.json
	sed -i "s/<user>/$MQ_USER/" $SECPI_PATH/manager/config.json $SECPI_PATH/webinterface/config.json
	sed -i "s/<pwd>/$MQ_PWD/" $SECPI_PATH/manager/config.json $SECPI_PATH/webinterface/config.json
	
	sed -i "s/<certfile>/manager.$CA_DOMAIN.cert.pem/" $SECPI_PATH/manager/config.json
	sed -i "s/<keyfile>/manager.$CA_DOMAIN.key.pem/" $SECPI_PATH/manager/config.json
	
	sed -i "s/<certfile>/webui.$CA_DOMAIN.cert.pem/" $SECPI_PATH/webinterface/config.json
	sed -i "s/<keyfile>/webui.$CA_DOMAIN.key.pem/" $SECPI_PATH/webinterface/config.json
	sed -i "s/<server_cert>/$WEB_CERT_NAME.$CA_DOMAIN.cert.pem/" $SECPI_PATH/webinterface/config.json
	sed -i "s/<server_key>/$WEB_CERT_NAME.$CA_DOMAIN.key.pem/" $SECPI_PATH/webinterface/config.json
	

	echo "Generating rabbitmq certificates..."
	gen_and_sign_cert manager.$CA_DOMAIN client
	gen_and_sign_cert webui.$CA_DOMAIN client
	
	echo "Generating webserver certificate..."
	gen_and_sign_cert $WEB_CERT_NAME.$CA_DOMAIN server

	echo "Creating htdigest file..."
	webinterface/create_htdigest.sh $SECPI_PATH/webinterface/.htdigest $WEB_USER $WEB_PWD
	
	
	echo "Copying startup scripts..."
	
	cp scripts/secpi-manager /etc/init.d/
	sed -i "s/{{DEAMONUSER}}/$SECPI_USER:$SECPI_GROUP/" /etc/init.d/secpi-manager
	
	cp scripts/secpi-manager.service /etc/systemd/system/
	sed -i "s/User=/User=$SECPI_USER/" /etc/systemd/system/secpi-manager.service
	sed -i "s/Group=/Group=$SECPI_GROUP/" /etc/systemd/system/secpi-manager.service
	
	update-rc.d secpi-manager defaults
	
	
	
	cp scripts/secpi-webinterface /etc/init.d/
	sed -i "s/{{DEAMONUSER}}/$SECPI_USER:$SECPI_GROUP/" /etc/init.d/secpi-webinterface
	
	cp scripts/secpi-webinterface.service /etc/systemd/system/
	sed -i "s/User=/User=$SECPI_USER/" /etc/systemd/system/secpi-webinterface.service
	sed -i "s/Group=/Group=$SECPI_GROUP/" /etc/systemd/system/secpi-webinterface.service
	
	update-rc.d secpi-webinterface defaults
	
	# set permissions
	chmod 755 $SECPI_PATH/webinterface/main.py
	chmod 755 $SECPI_PATH/manager/manager.py
fi


# worker or complete install
if [ $INSTALL_TYPE -eq 1 ] || [ $INSTALL_TYPE -eq 3 ]
then
	echo "Copying worker..."
	cp -R worker/ $SECPI_PATH/
	
	sed -i "s/<ip>/$MQ_IP/" $SECPI_PATH/worker/config.json
	sed -i "s/<port>/$MQ_PORT/" $SECPI_PATH/worker/config.json
	sed -i "s/<user>/$MQ_USER/" $SECPI_PATH/worker/config.json
	sed -i "s/<pwd>/$MQ_PWD/" $SECPI_PATH/worker/config.json
	
	sed -i "s/<certfile>/worker1.$CA_DOMAIN.cert.pem/" $SECPI_PATH/worker/config.json
	sed -i "s/<keyfile>/worker1.$CA_DOMAIN.key.pem/" $SECPI_PATH/worker/config.json
	
	gen_and_sign_cert worker1.$CA_DOMAIN client
	
	echo "Copying startup scripts..."
	cp scripts/secpi-worker /etc/init.d/
	sed -i "s/{{DEAMONUSER}}/$SECPI_USER:$SECPI_GROUP/" /etc/init.d/secpi-worker
	
	cp scripts/secpi-worker.service /etc/systemd/system/
	sed -i "s/User=/User=$SECPI_USER/" /etc/systemd/system/secpi-worker.service
	sed -i "s/Group=/Group=$SECPI_GROUP/" /etc/systemd/system/secpi-worker.service
	
	update-rc.d secpi-worker defaults
	
	
	# set permissions
	chmod 755 $SECPI_PATH/worker/worker.py
fi

chown -R $SECPI_USER:$SECPI_GROUP $SECPI_PATH

# reload systemd, but don't write anything if systemctl doesn't exist
systemctl daemon-reload > /dev/null 2>&1


cp scripts/gen_cert.sh $SECPI_PATH

################################################################################################

echo "Installing python requirements..."
pip install -r requirements.txt
if [ $? -ne 0 ];
then
	echo "Error installing requirements!"
	exit 1
fi


echo "#####################################################"
echo "SecPi sucessfully installed!"
echo "#####################################################"
################
exit 0
################

