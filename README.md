Virtualhost Manage Script
===========

Bash Script to allow create or delete apache/nginx virtual hosts on Ubuntu on a quick way.

## Installation ##

1. Download the script
2. Apply permission to execute:

```
$ chmod +x /path/to/vhost.sh
```

3. Optional: if you want to use the script globally, then you need to copy the file to your /usr/local/bin directory, is better
if you copy it without the .sh extension:

```bash
$ sudo cp /path/to/vhost.sh /usr/local/bin/vhost
```

### For Global Shortcut ###

```bash
$ cd /usr/local/bin
$ wget -O vhost https://raw.githubusercontent.com/brajky/vhost/master/vhost.sh
$ chmod +x vhost
$ wget -O vhostx https://raw.githubusercontent.com/brajky/vhost/master/vhostx.sh
$ chmod +x vhostx
```

## Usage ##

Basic command line syntax:

```bash
$ sudo sh /path/to/vhost.sh [create | delete] [domain] [optional host_dir]
```

With script installed on /usr/local/bin

```bash
$ sudo vhost [create | delete] [domain] [optional host_dir]
```

### Examples ###

to create a new virtual host:

```bash
$ sudo vhost create mysite.dev
```
to create a new virtual host with custom directory name:

```bash
$ sudo vhost create anothersite.dev my_dir
```
to delete a virtual host

```bash
$ sudo vhost delete mysite.dev
```

to delete a virtual host with custom directory name:

```
$ sudo vhost delete anothersite.dev my_dir
```