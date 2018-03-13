# ad_nslcd
Linux integration for AD using nslcd. Features linux system, sudo, SSH Password, SSH Public Key Authentication


# How to apply
  1. Install puppet. This is tested with puppet3\
     `yum install puppet3`
     
  2. This integration stdlib from puppetlabs. Some distribution have this already, if not, install it\
     ```
     #Check if you have puppet stdlib
     puppet module list
     
     #Install it
     pupppet module install puppetlabs-stdlib --version 4.24.0
     ```
  3. Apply the manifest file
     `puppet apply adnslcd.pp`
