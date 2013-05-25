Virtualhost Manage Bash Script
===========

Bash Script to allow easy create or delete apache virtual hosts on ubuntu.

## Installation ##

1.- Download the script
2.- Apply permission to execute:

  $ chmod +x /path/to/virtualhost.sh
  
Optional: if you want to use the script globally, then you need to copy the file to your /usr/local/bin directory, is better
if you copy it without the .sh extension:

  sudo cp /path/to/virtualhost.sh /usr/local/bin/virtualhost

## Usage ##

  $ sudo virtualhost \[crate | delete] \[domain] \[host_dir]

to create a new virtual host with the same directory name as domain:

  $ sudo virtualhost create mysite.dev
  
to create a new virtual host with custom directory name or using existing one (relative to /var/www):

  $ sudo virtualhost create anothersite.dev my_dir
  
to delete a virtual host

  $ sudo virtualhost delete mysite.dev
  
to delete a virtual host with custom directory name

  $ sudo virtualhost delete anothersite.dev my_dir

