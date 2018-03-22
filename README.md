# ad_nslcd
Linux integration for AD using nslcd. Features linux system, sudo, SSH Password, SSH Public Key Authentication. This puppet manifest file is designed to be stand alone and master-less to minimize dependency on other existing systems.

# Pre-flight check
Before applying this manifest, make sure that the following checks are performed to prevent being locked out of the instance
  1. TCP connectivity from the instance to the AD server's port 389 is established
     ```telnet <ad-server> 389```
  2. Bind user or service account user can authenticate to the AD server
     ```ldapsearch -x  -W -H ldap://<ad-server>:389 -D '<bind-user>' -b 'DC=LAUNCHPAD,DC=CORP,DC=VOYAGERINNOVATION,DC=COM'```
  3. Verify AD server's certificate
  4. Get the instance's SSH AD group from your AD Administrator e.g. SE



# How to apply
  1. Install puppet. This is tested with puppet3\
     `yum install puppet3`
     
  2. This integration stdlib from puppetlabs. Some distribution have this already, if not, install it
     ```
     #Check if you have puppet stdlib
     puppet module list
     
     #Install it
     puppet module install puppetlabs-stdlib --version 4.24.0
     ```
  3. Clone this repo
     `git clone https://github.com/VoyagerInnovations/ad_nslcd.git`
  4. Copy custom facter to the correct folder
      ```
      mkdir -p /etc/facter/facts.d
      cp ad_nslcd/facter/* /etc/facter/facts.d/
      chmod +x /etc/facter/facts.d/*
      ```
  5. Update the following parameters in the adnslcd.pp manifest. You should get the information from your AD administrator
      ```
      $ad_ip_1="1.1.1.1"
      $ad_ip_2="2.2.2.2"
      $ad_port_1="389"
      $ad_port_2="389"
      $ad_hostname_1="<ad-hostname-1>"
      $ad_hostname_2="<ad-hostname-2>"
      $ad_binddn="<bind-user>"
      $ad_bindpw="<bind-password>"
      $ad_base_search="dc=launchpad,dc=corp,dc=voyagerinnovation,dc=com"
      $ad_sudo_base_search="OU=SUDOers,OU=Security Groups,OU=Groups,$ad_base_search"
      $ad_ssh_allow_groups="<se-group> root"
      $linux_breakglass_account="<service/breakglass account>"
      ```
  6. Apply the manifest file\
     `puppet apply adnslcd.pp`
