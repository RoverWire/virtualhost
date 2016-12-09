#!/bin/bash
### Set Language
TEXTDOMAIN=virtualhost

### Set default parameters
action=$1
domain=$2
adminMail=$3
rootDir=$4
owner=$(who am i | awk '{print $1}')
nginxSitesEnable='/etc/nginx/sites-enabled/'
nginxSitesAvailable='/etc/nginx/sites-available/'
apacheSitesEnable='/etc/apache2/sites-enabled/'
apacheSitesAvailable='/etc/apache2/sites-available/'
userDir='/var/www/'

if [ "$(whoami)" != 'root' ]; then
	echo $"You have no permission to run $0 as non-root user. Use sudo"
		exit 1;
fi

if [ "$action" != 'create' ] && [ "$action" != 'delete' ]
	then
		echo $"You need to prompt for action (create or delete) -- Lower-case only"
		exit 1;
fi

while [ "$domain" == "" ]
do
	echo -e $"Please provide domain. e.g.dev,staging"
	read domain
done

if [ "$rootDir" == "" ]; then
	rootDir=${domain}
fi

if [ "$adminMail" == "" ]; then
	adminMail='admin@yourserver.com'
fi

### if root dir starts with '/', don't use /var/www as default starting point
if [[ "$rootDir" =~ ^/ ]]; then
	userDir=''
fi

if [ "$action" == 'create' ]
	then
		### check if Nginx domain already exists
		if [ -e $nginxSitesAvailable$domain ]; then
			echo -e $"This Nginx domain already exists.\nPlease Try Another one"
			exit;
		fi

		### check if Apache domain already exists
		if [ -e $apacheSitesAvailable$domain ]; then
			echo -e $"This Apache domain already exists.\nPlease Try Another one"
			exit;
		fi

		### check if directory exists or not
		if ! [ -d $userDir$rootDir ]; then

			### create the directory
			mkdir $userDir$rootDir

			### create files and logs directories
			mkdir $userDir$rootDir/files
			mkdir $userDir$rootDir/logs

			### give permission to root dir
			chmod 755 $userDir$rootDir

			### give permissions to files and logs folders
			chmod 755 $userDir$rootDir/files
			chmod 755 $userDir$rootDir/logs

			### write test file in the new domain dir
			if ! echo "<?php echo phpinfo(); ?>" > $userDir$rootDir/files/phpinfo.php
				then
					echo $"ERROR: Not able to write in file $userDir$rootDir/files/phpinfo.php. Please check permissions."
					exit;
			else
					echo $"Added content to $userDir$rootDir/files/phpinfo.php."
			fi
		fi

		### create Nginx virtual host rules file
		if ! echo "
			server {
		        listen 80;
		        listen [::]:80;

		        root $userDir$rootDir/files;

		        server_name $domain;


		        location / {
		                proxy_pass http://127.0.0.1:81;
		                proxy_set_header Host \$host;
		                proxy_set_header X-Real-IP \$remote_addr;
		                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		                proxy_set_header X-Forwarded-Proto \$scheme;
		        }

		        location ~ \.(html|jpeg|jpg|gif|png|css|js|pdf|txt|tar|ico)$ {
		                root $userDir$rootDir/files;
		        }
			}
		" > $nginxSitesAvailable$domain
		then
			echo -e $"There is an ERROR create Nginx $domain file"
			exit;
		else
			echo -e $"\nNew Virtual Nginx Host Created\n"
		fi

		### create Apache virtual host rules file
		if ! echo "
			<VirtualHost *:81>
		        ServerName $domain

		        ServerAdmin $adminMail
		        DocumentRoot $userDir$rootDir/files

		        ErrorLog $userDir$rootDir/logs/error.log
		        CustomLog $userDir$rootDir/logs/access.log combined
			</VirtualHost>

			<IfModule remoteip_module>
			RemoteIPHeader X-Forwarded-For
			RemoteIPTrustedProxy 127.0.0.1
			</IfModule>
		" > $apacheSitesAvailable$domain
		then
			echo -e $"There is an ERROR create Apache $domain file"
			exit;
		else
			echo -e $"\nNew Virtual Apache Host Created\n"
		fi

		### Add domain in /etc/hosts
		if ! echo "127.0.0.1	$domain" >> /etc/hosts
			then
				echo $"ERROR: Not able write in /etc/hosts"
				exit;
		else
				echo -e $"Host added to /etc/hosts file \n"
		fi

		if [ "$owner" == "" ]; then
			chown -R $(whoami):www-data $userDir$rootDir
		else
			chown -R $owner:www-data $userDir$rootDir
		fi

		### enable Nginx website
		ln -s $nginxSitesAvailable$domain $nginxSitesEnable$domain

		### enable Apache website
		ln -s $apacheSitesAvailable$domain $apacheSitesEnable$domain

		### restart Nginx
		service nginx restart

		### restart Apache
		service apache2 restart

		### show the finished message
		echo -e $"Complete! \nYou now have a new Virtual Host \nYour new host is: http://$domain \nAnd its located at $userDir$rootDir"
		exit;
	else
		### check whether domain already exists
		if ! [ -e $nginxSitesAvailable$domain ]; then
			echo -e $"This domain dont exists.\nPlease Try Another one"
			exit;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts

			### disable website Nginx
			rm $nginxSitesEnable$domain

			### disable website Apache
			rm $apacheSitesEnable$domain

			### restart Nginx
			service nginx restart

			### restart Apache
			service apache2 restart

			### Delete Nginx virtual host rules files
			rm $nginxSitesAvailable$domain

			### Delete Apache virtual host rules files
			rm $apacheSitesAvailable$domain
		fi

		### check if directory exists or not
		if [ -d $userDir$rootDir ]; then
			echo -e $"Delete host root directory ? (s/n)"
			read deldir

			if [ "$deldir" == 's' -o "$deldir" == 'S' ]; then
				### Delete the directory
				rm -rf $userDir$rootDir
				echo -e $"Directory deleted"
			else
				echo -e $"Host directory conserved"
			fi
		else
			echo -e $"Host directory not found. Ignored"
		fi

		### show the finished message
		echo -e $"Complete!\nYou just removed Virtual Host $domain"
		exit 0;
fi
