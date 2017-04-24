#!/bin/bash
### Set Language
TEXTDOMAIN=vhost-minion
### Set default parameters
action=$1
domain=$2
rootDir=$3
owner=$(who am I | awk '{print $1}')
email='webmaster@localhost'
sitesEnable='/etc/apache2/sites-enabled/'
sitesAvailable='/etc/apache2/sites-available/'
userDir='/var/www/'
sitesAvailabledomain=$sitesAvailable$domain.conf

### don't modify from here unless you know what you are doing ####
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if (( "${BASH_VERSION%%[^0-9]*}" < 4 )); then
	echo -e $"${RED}You need at least bash version 4${NC}"
	exit 1;
fi

if [ "$(whoami)" != 'root' ]; then
	echo -e $"${RED}You have no permission to run $0 as non-root user. Use sudo${NC}"
	exit 1;
fi

if [ "${action,,}" != 'create' ] && [ "${action,,}" != 'delete' ]; then
	echo -e $"${RED}You need to prompt for action (create or delete)${NC}"
	exit 1;
fi

if [ "$domain" == "" ]; then
	echo -e $"${GREEN}Please provide domain. e.g.dev, staging, local...${NC}"
	read domain
	sitesAvailabledomain=$sitesAvailable$domain.conf
fi

if [ "$rootDir" == "" ]; then
	rootDir=$domain
fi
### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

rootDir=$userDir$rootDir

if [ "${action,,}" == 'create' ]; then
		### check if domain already exists
		if [ -e $sitesAvailabledomain ]; then
			echo -e $"${RED}This domain already exists.\nPlease Try Another one${NC}"
			echo $sitesAvailabledomain
			exit 1;
		fi
		### check if directory exists or not
		if ! [ -d "$rootDir" ]; then
			### create the directory
			mkdir "$rootDir"
			### give permission to root dir
			chmod 755 "$rootDir"
			### write test file in the new domain dir
			if ! echo "working" > "$rootDir/index.php"; then
				echo -e $"${RED}Not able to write in file $rootDir/index.php. Please check permissions${NC}"
				exit 1;
			else
				echo -e $"${YELLOW}Added content to $rootDir/index.php${NC}"
			fi
		fi

		### create virtual host rules file
		if ! echo "
		<VirtualHost *:80>
			ServerAdmin $email
			ServerName $domain
			ServerAlias $domain
			DocumentRoot $rootDir
			<Directory />
				AllowOverride All
			</Directory>
			<Directory $rootDir>
				Options Indexes FollowSymLinks MultiViews
				AllowOverride all
				Require all granted
			</Directory>
			ErrorLog /var/log/apache2/$domain-error.log
			LogLevel error
			CustomLog /var/log/apache2/$domain-access.log combined
		</VirtualHost>" > "$sitesAvailabledomain"; then
			echo -e $"${RED}There is an ERROR creating $domain file${NC}"
			exit 1;
		else
			echo -e $"\n${YELLOW}New Virtual Host Created\n${NC}"
		fi
		# Ask to add domain in /etc/hosts
		echo -e $"${GREEN}Add domain to /etc/hosts ? (y/n)${NC}"
			read addhosts

			if [ "${addhosts,,}" == 'y' ] || [ "${addhosts,,}" == 'yes' ]; then
				### Add domain in /etc/hosts
				if ! echo "127.0.0.1	$domain" >> /etc/hosts; then
					echo -e $"${RED}Not able to write in /etc/hosts${NC}"
					exit 1;
				else
					echo -e $"${YELLOW}Host added to /etc/hosts file${NC} \n"
				fi

				if [ "$owner" == "" ]; then
					chown -R $(whoami):$(whoami) "$rootDir"
				else
					chown -R "$owner":"$owner" "$rootDir"
				fi
			fi
		### enable website
		a2ensite "$domain"
		### restart Apache
		/etc/init.d/apache2 reload
		### show the finished message
		echo -e $"${YELLOW}Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $rootDir${NC}"
		exit 0;
	else
		### check whether domain already exists
		if ! [ -e "$sitesAvailabledomain" ]; then
			echo -e $"${RED}This domain does not exist.\nPlease try another one${NC}"
			exit 1;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts
			### disable website
			a2dissite "$domain"
			### restart Apache
			/etc/init.d/apache2 reload
			### Delete virtual host rules files
			rm "$sitesAvailabledomain"
		fi
		### check if directory exists or not
		if [ -d "$rootDir" ]; then
			echo -e $"${GREEN}Delete host root directory ? (y/n)${NC}"
			read deldir

			if [ "${deldir,,}" == 'y' ] || [ "${deldir,,}" == 'yes' ]; then
				### Delete the directory
				rm -rf "$rootDir"
				echo -e $"${YELLOW}Directory deleted${NC}"
			else
				echo -e $"${YELLOW}Host directory conserved${NC}"
			fi
		else
			echo -e $"${YELLOW}Host directory not found. Ignored${NC}"
		fi
		### show the finished message
		echo -e $"${YELLOW}Complete!\nYou just removed Virtual Host $domain ${NC}"
		exit 0;
fi