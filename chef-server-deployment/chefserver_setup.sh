#!/bin/bash
# setup chef server and chef workstation

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
###########################################################
#                setup for chef server                    #
###########################################################
# create home folder in first login
if [ ! -e /home/auto ]; then
    mkdir /home/auto
fi
cd /home/auto

# ensure that the VM name is the same with the beginning of fqdn in Azure template
hostname=`hostname`
chef_fqdn="${hostname}.eastasia.cloudapp.azure.com"
# change the FQDN for the ubuntu server before installing chef server
sudo echo "127.0.1.1 ${chef_fqdn} ${hostname}" >> /etc/hosts
sudo service hostname restart
res=`hostname -f`
if [ $res != $chef_fqdn ]; then
    echo "changing FQDN fail!"
    exit 1
fi

# download chef server
wget $chef_server_url
if [ $? != 0 ]; then
    echo "download chef server fail!"
    exit 2
fi

# install chef server
sudo dpkg -i $chef_server_deb
if [ $? != 0 ]; then
    echo "dpkg install chef server fail!"
    exit 3
fi

# config chef server
sudo chef-server-ctl reconfigure
if [ $? != 0 ]; then
    echo "reconfigure chef server fail!"
    exit 4
fi

# install opscode-manage
sudo chef-server-ctl install opscode-manage
if [ $? != 0 ]; then
    echo "opscode-manage install fail!"
    exit 5
fi

# config opscode-manage
sudo opscode-manage-ctl reconfigure
if [ $? != 0 ]; then
    echo "opscode-manage reconfigure fail!"
    exit 6
fi

# create a new administor user
chef-server-ctl user-create $chef_admin_user sosse sosse auto@auto.com $chef_damin_pw --filename $chef_admin_pem
if [ $? != 0 ]; then
    echo "create chef server admin fail!"
    exit 6
fi

# create a new organization
chef-server-ctl org-create $chef_org_name "sosse, Inc." --association_user $chef_admin_user --filename $chef_org_pem
if [ $? != 0 ]; then
    echo "create chef server organization fail!"
    exit 7
fi

###########################################################
#                setup for chef workstation               #
###########################################################
# install all dependent packages
sudo apt-get -y update
sudo apt-get install -y git ruby1.9.1-full ruby make g++ zlib1g-dev

# download chef client
wget $chef_client_url
if [ $? != 0 ]; then
    echo "download chef client fail!"
    exit 8
fi

# install chef client
sudo dpkg -i $chef_client_deb
if [ $? != 0 ]; then
    echo "dpkg install chef client fail!"
    exit 9
fi

# clone chef-repo
git clone https://github.com/chef/chef-repo.git
if [ ! -e ./chef-repo ]; then
    echo "clone chef-repo fail!"
    exit 10
fi

# copy <user>.pem <org>.pem knife.rb to .chef 
mkdir ./chef-repo/.chef

knife_config="# See https://docs.getchef.com/config_rb_knife.html for more information on knife configuration options

current_dir = File.dirname(__FILE__)
log_level                :info
log_location             STDOUT
node_name                \"${chef_admin_user}\"
client_key               \"#{current_dir}/${chef_admin_user}.pem\"
validation_client_name   \"${chef_org_name}-validator\"
validation_key           \"#{current_dir}/${org}-validator.pem\"
chef_server_url          \"https://${chef_fqdn}/organizations/${chef_org_name}\"
cookbook_path            [\"#{current_dir}/../cookbooks\"]"

echo "$knife_config" > knife.rb

cp $chef_admin_pem ./chef-repo/.chef
cp $chef_org_pem ./chef-repo/.chef
cp knife.rb ./chef-repo/.chef
cd ./chef-repo
knife ssl fetch

res=`knife user list`
if [ $res != $chef_admin_user ]; then
    echo "knife ssl fetch fail!"
    exit 11
fi

# download chef dk
wget $chef_dk_url
if [ $? != 0 ]; then
    echo "download chef dk fail!"
    exit 12
fi

# install chef client
sudo dpkg -i $chef_dk_deb
if [ $? != 0 ]; then
    echo "dpkg install chef dk fail!"
    exit 13
fi

# update the bash env for chef
`chef shell-init bash`

# install knife winodws plugin
sudo gem install knife-windows
if [ $? != 0 ]; then
    echo "install knife-winodows plugin fail!"
    exit 14
fi

