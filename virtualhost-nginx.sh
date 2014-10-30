#!/bin/bash
### Set default parameters
action=$1
domain=$2
rootdir=$3
owner=$(who am i | awk '{print $1}')
sitesEnable='/etc/nginx/sites-enabled/'
sitesAvailable='/etc/nginx/sites-available/'
userDir='/var/www/'
 
if [ "$(whoami)" != 'root' ]; then
  	echo "You have no permission to run $0 as non-root user. Use sudo"
		exit 1;
fi
 
if [ "$action" != 'create' ] && [ "$action" != 'delete' ] 
	then
		echo "You need to prompt for action (create or delete) -- Lower-case only"
		exit 1;
fi
 
while [ "$domain" == ""  ]
do
	echo -e "Please provide domain. e.g.dev,staging"
	read  domain
done
 
if [ "$rootdir" == "" ]; then
	rootdir=${domain//./}
fi
 
if [ "$action" == 'create' ] 
	then
		### check if domain already exists
		if [ -e $sitesAvailable$domain ]; then
			echo -e 'This domain already exists.\nPlease Try Another one'
			exit;
		fi
 
		### check if directory exists or not
		if ! [ -d $userDir$rootdir ]; then
			### create the directory
			mkdir $userDir$rootdir
			### give permission to root dir
			chmod 755 $userDir$rootdir
			### write test file in the new domain dir
			if ! echo "<?php echo phpinfo(); ?>" > $userDir$rootdir/phpinfo.php
			then
				echo "ERROR: Not able to write in file "$userDir"/"$rootdir"/phpinfo.php. Please check permissions."
				exit;
			else
				echo "Added content to "$userDir$rootdir"/phpinfo.php."
			fi
		fi
 
		### create virtual host rules file
		if ! echo "server {
	listen   80;
	root $userDir$rootdir;
	index index.php index.html index.htm;
	server_name $domain www.$domain;

	# serve static files directly
	location ~* \.(jpg|jpeg|gif|css|png|js|ico|html)$ {
		access_log off;
		expires max;
	}

	# removes trailing slashes (prevents SEO duplicate content issues)
	if (!-d \$request_filename) {
		rewrite ^/(.+)/\$ /\$1 permanent;
	}

	# unless the request is for a valid file (image, js, css, etc.), send to bootstrap
	if (!-e \$request_filename) {
		rewrite ^/(.*)\$ /index.php?/\$1 last;
		break;
	}

	# removes trailing 'index' from all controllers
	if (\$request_uri ~* index/?\$) {
		rewrite ^/(.*)/index/?\$ /\$1 permanent;
	}

	# catch all
	error_page 404 /index.php;
	
	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)\$;
		fastcgi_pass 127.0.0.1:9000;
		fastcgi_index index.php;
		include fastcgi_params;
	}

	location ~ /\.ht {
		deny all;
	}

}" > $sitesAvailable$domain
		then
			echo -e 'There is an ERROR create $domain file'
			exit;
		else
			echo -e '\nNew Virtual Host Created\n'
		fi
 
		### Add domain in /etc/hosts
		if ! echo "127.0.0.1	$domain" >> /etc/hosts
		then
			echo "ERROR: Not able write in /etc/hosts"
			exit;
		else
			echo -e "Host added to /etc/hosts file \n"
		fi
 
		if [ "$owner" == ""  ]; then
			chown -R $(whoami):www-data $userDir$rootdir
		else
			chown -R $owner:www-data $userDir$rootdir
		fi

		### enable website
		ln -s $sitesAvailable$domain $sitesEnable$domain
 
		### restart Nginx
		service nginx restart
 
		### show the finished message
		echo -e "Complete! \nYou now have a new Virtual Host \nYour new host is: http://"$domain" \nAnd its located at "$userDir$rootdir
		exit;
	else
		### check whether domain already exists
		if ! [ -e $sitesAvailable$domain ]; then
			echo -e 'This domain dont exists.\nPlease Try Another one'
			exit;
		else
			### Delete domain in /etc/hosts
			newhost=${domain//./\\.}
			sed -i "/$newhost/d" /etc/hosts

			### disable website
			rm $sitesEnable$domain
	 
			### restart Nginx
			service nginx restart

			### Delete virtual host rules files
			rm $sitesAvailable$domain
		fi
 
		### check if directory exists or not
		if [ -d $userDir$rootdir ]; then
			echo -e 'Delete host root directory ? (s/n)'
			read deldir

			if [ "$deldir" == 's' -o "$deldir" == 'S' ]; then
				### Delete the directory
				rm -rf $userDir$rootdir
				echo -e 'Directory deleted'
			else
				echo -e 'Host directory conserved'
			fi
		else
			echo -e 'Host directory not found. Ignored'
		fi
 
		### show the finished message
		echo -e "Complete!\nYou just removed Virtual Host "$domain
		exit 0;
fi
