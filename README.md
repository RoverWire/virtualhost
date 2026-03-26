Virtualhost Manager Script
===========

Bash Script to allow create or delete apache/nginx virtual hosts on Ubuntu on a easy way.

## Installation ##

1. Download the script
2. Apply permission to execute:

```
$ chmod +x /path/to/virtualhost.sh
```

3. Optional: To use the script globally, copy it to the /usr/local/bin directory. It is recommended to remove the .sh extension.

```bash
$ sudo cp /path/to/virtualhost.sh /usr/local/bin/virtualhost
```

### For Global Shortcut ###

```bash
$ cd /usr/local/bin
$ wget -O virtualhost https://raw.githubusercontent.com/RoverWire/virtualhost/master/virtualhost.sh
$ chmod +x virtualhost
$ wget -O virtualhost-nginx https://raw.githubusercontent.com/RoverWire/virtualhost/master/virtualhost-nginx.sh
$ chmod +x virtualhost-nginx
```

## Usage ##

Basic command line syntax:

```bash
$ sudo sh /path/to/virtualhost.sh [create | delete] [domain] [optional root_dir] [optional is_subdomain] [optional canonical]
```

With script installed on /usr/local/bin

```bash
$ sudo virtualhost [create | delete] [domain] [optional root_dir] [optional is_subdomain] [optional canonical]
```
Parameters:
- `domain` is the domain name for the virtualhost (myhomepage.com, test.local, etc)
- `root_dir` is the path where your want to serv as domain root for your host files. If not specified it will create a new one under /var/www folder.
- `is_subdomain` is a boolean true/false to flag when a host is subdomain.
- `canonical` can have two possible values: www or empty, this is to add another entry in the hosts files preppending the www.

### Examples ###

to create a new virtual host:

```bash
$ sudo virtualhost create mysite.dev
```
to create a new virtual host with custom directory name:

```bash
$ sudo virtualhost create anothersite.dev my_dir
```
to delete a virtual host

```bash
$ sudo virtualhost delete mysite.dev
```

to delete a virtual host with custom directory name:

```
$ sudo virtualhost delete anothersite.dev my_dir
```
### Localization

WARNING: Localizations are outdated, any help to contribute to fix this is welcome.

For Apache:

```bash
$ sudo cp /path/to/locale/<language>/virtualhost.mo /usr/share/locale/<language>/LC_MESSAGES/
```

For NGINX:

```bash
$ sudo cp /path/to/locale/<language>/virtualhost-nginx.mo /usr/share/locale/<language>/LC_MESSAGES/
```
### Contributions

Contributions are welcome. You can also report any issues.

Thank you to [everyone who has contributed](https://github.com/RoverWire/virtualhost/graphs/contributors) over the years.
