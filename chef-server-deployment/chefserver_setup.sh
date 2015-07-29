#!/bin/bash
# setup chef server and chef workstation
#
# Usage: $proganme <Azure location string>
# <Azure location string>: e.g "East Asia", "West US", script will modify
#                          machine FQDN according to this string

# variables
chef_server_deb="chef-server-core_12.1.0-1_amd64.deb"
chef_server_url="https://web-dl.packagecloud.io/chef/stable/packages/ubuntu/trusty/${chef_server_deb}"
chef_admin_user="auto"
chef_damin_pw="Dell@123"
chef_admin_pem="/home/auto/${chef_admin_user}.pem"
chef_org_name="chef"
chef_org_pem="/home/auto/${chef_org_name}-validator.pem"
chef_client_deb="chef_12.4.1-1_amd64.deb"
chef_client_url="https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/10.04/x86_64/${chef_client_deb}"
chef_dk_deb="chefdk_0.6.2-1_amd64.deb"
chef_dk_url="https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/${chef_dk_deb}"
vm_admin_user="auto"
download_retry_count=3
download_retry_interval=10

# functions

# Function used to download deb package from network
func_download_deb()
{
    wget $1
    res=$?
    i=0
    # retry if fail
    while [ $i -lt $download_retry_count ] && [ $res -ne 0 ]; do
        # remove the invalid download file before retry
        rm -f $2
        sleep $download_retry_interval
        echo "retrying the ${i}th time"
        wget $1
        res=$?
        i=$((i+1))
    done
    if [ $res -ne 0 ]; then
        echo "download fail!"
        exit 2
    fi
}
###########################################################
#                for chef server                          #
###########################################################
# create home folder in first login
if [ ! -e /home/$vm_admin_user ]; then
    mkdir /home/$vm_admin_user
fi
cd /home/$vm_admin_user

# ensure that the VM name is the same with the beginning of fqdn 
# in Azure template
hostname=`hostname`
# $1 is the Azure location string, e.g. 'East Asia', 'West US'
# need to remove the space and make all characters to lowwer case
location=`echo $1 | sed -e "s/ //g" | tr "[A-Z]" "[a-z]"`
chef_fqdn="${hostname}.${location}.cloudapp.azure.com"
# change the FQDN for the ubuntu server before installing chef 
# server, because it will use FQDN as the server url
sudo echo "127.0.1.1 ${chef_fqdn} ${hostname}" >> /etc/hosts
sudo service hostname restart
echo "Changing FQDN to ${chef_fqdn}"
# check if the FQDN is as expected
res=`hostname -f`
if [ $res != $chef_fqdn ]; then
    echo "changing FQDN fail!"
    exit 1
fi

# download chef server, and retry if fail some time
echo "Downloading chef server"
func_download_deb $chef_server_url $chef_server_deb

# install chef server
echo "Installing chef server"
sudo dpkg -i $chef_server_deb
if [ $? != 0 ]; then
    echo "dpkg install chef server fail!"
    exit 3
fi
rm $chef_server_deb

# reconfigure subcommand is used when configure changes are made to
# chef server (normally chef-server.rb is modified). And after server
# is installed, need to do configure
echo "chef-server-ctl reconfigure"
sudo chef-server-ctl reconfigure
if [ $? != 0 ]; then
    echo "reconfigure chef server fail!"
    exit 4
fi

# install opscode-manage
echo "Installing opscode-manage module"
sudo chef-server-ctl install opscode-manage
if [ $? != 0 ]; then
    echo "opscode-manage install fail!"
    exit 5
fi

# config opscode-manage
echo "opscode-manage-ctl reconfigure"
sudo opscode-manage-ctl reconfigure
if [ $? != 0 ]; then
    echo "opscode-manage reconfigure fail!"
    exit 6
fi

# create a new administor user, generate the private key
echo "Creating admin user: $chef_admin_user"
chef-server-ctl user-create $chef_admin_user sosse sosse auto@auto.com $chef_damin_pw --filename $chef_admin_pem
if [ $? != 0 ]; then
    echo "create chef server admin fail!"
    exit 7
fi

# create a new organization, associate the new administor user to 
# this organization, generate the validation key which is needed
# for the first connection between chef client and chef server
echo "Creating organization: $chef_org_name"
chef-server-ctl org-create $chef_org_name "sosse, Inc." --association_user $chef_admin_user --filename $chef_org_pem
if [ $? != 0 ]; then
    echo "create chef server organization fail!"
    exit 8
fi

###########################################################
#                setup chef workstation                   #
###########################################################
# install all dependent packages
echo "install all dependent packages"
sudo apt-get -y update
sudo apt-get install -y git ruby1.9.1-full ruby make g++ zlib1g-dev

# download chef client, and retry if fail some time
echo "Downloading chef client"
func_download_deb $chef_client_url $chef_client_deb

# install chef client
echo "Installing chef client"
sudo dpkg -i $chef_client_deb
if [ $? != 0 ]; then
    echo "dpkg install chef client fail!"
    exit 9
fi
rm $chef_client_deb

# clone chef-repo from github, and this is the working folder of chef
# workstation. All cookbooks are stored inside chef-repo.
echo "Clone chef-repo"
git clone https://github.com/pennyliangliping/chef-repo.git
if [ ! -e ./chef-repo ]; then
    echo "clone chef-repo fail!"
    exit 10
fi

# when workstation connect to chef server, it needs to know the server
# information and have authentication method. Folder .chef includes
# all these things: 
# <admin>.pem <validation>.pem -- private key for authentication
# knife.rb -- includes server information
#
# move <admin>.pem <validation>.pem knife.rb to .chef folder
mkdir ./chef-repo/.chef

echo "Copy knife.rb validation.pem admin.pem to .chef folder"
knife_config="# See https://docs.getchef.com/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                \"${chef_admin_user}\"
client_key               \"#{current_dir}/${chef_admin_user}.pem\"
validation_client_name   \"${chef_org_name}-validator\"
validation_key           \"#{current_dir}/${chef_org_name}-validator.pem\"
chef_server_url          \"https://${chef_fqdn}/organizations/${chef_org_name}\"
cookbook_path            [\"#{current_dir}/../cookbooks\"]"

# generate knife.rb file"
echo "$knife_config" > knife.rb

mv $chef_admin_pem ./chef-repo/.chef
mv $chef_org_pem ./chef-repo/.chef
mv knife.rb ./chef-repo/.chef
cd ./chef-repo
knife ssl fetch

# check if the connection between workstation and server is OK
res=`knife user list`
if [ $res != $chef_admin_user ]; then
    echo "knife ssl fetch fail!"
    exit 11
fi

# be careful for the cookbook upload order
# dependency may cause upload failure
echo "upload all cookbooks needed"
cd /home/$vm_admin_user/chef-repo/cookbooks
knife cookbook upload chef_handler
knife cookbook upload chef-sugar
knife cookbook upload openssl
knife cookbook upload windows
knife cookbook upload sql_server
knife cookbook upload sosse

cd /home/$vm_admin_user/chef-repo/

# download chef dk
echo "Downloading chef dk"
func_download_deb $chef_dk_url $chef_dk_deb

# install chef dk
echo "Installing chef dk"
sudo dpkg -i $chef_dk_deb
if [ $? != 0 ]; then
    echo "dpkg install chef dk fail!"
    exit 12
fi
rm $chef_dk_deb

## update the bash env for chef
#`chef shell-init bash`
#
## install knife winodws plugin
#sudo gem install knife-windows
#if [ $? != 0 ]; then
#    echo "install knife-winodows plugin fail!"
#    exit 13
#fi


# change the owner and group to normal user
cd /home/$vm_admin_user
sudo chown -R $vm_admin_user chef-repo/
sudo chgrp -R $vm_admin_user chef-repo/
