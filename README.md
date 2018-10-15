

Virtualhost Manage Script
===========

This script has been altered for support with CentOS7 

## Installation ##

1. Download the script 
 git clone https://github.com/XtraNull/virtualhost.git
2. move script to /root folder
2. Apply executable permissions:

```
$ chmod +x /path/to/virtualhost.sh
```



## Usage ##

Basic command line syntax:

```bash
$ sudo sh /path/to/virtualhost.sh [create | delete | makecert] [domain] [optional host_dir]
```

With script installed on /usr/local/bin

```bash
$ sudo virtualhost [create | delete | makecert] [domain] [optional host_dir]
```

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

