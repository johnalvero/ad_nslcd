# John Homer H Alvero
# 2 March 2018
# Voyager EIT SSH LDAP Integration
# 

$ad_ip_1=""
$ad_ip_2=""
$ad_port_1="389"
$ad_port_2="389"
$ad_hostname_1="xxxxxxx.LAUNCHPAD.CORP.VOYAGERINNOVATION.COM"
$ad_hostname_2="xxxxxxx.LAUNCHPAD.CORP.VOYAGERINNOVATION.COM"
$ad_binddn=""
$ad_bindpw=""
$ad_base_search="dc=launchpad,dc=corp,dc=voyagerinnovation,dc=com"
$ad_sudo_base_search="OU=SUDOers,OU=Security Groups,OU=Groups,$ad_base_search"
$ad_ssh_allow_groups="<group1> <group2> <etc>"
$linux_breakglass_account="<local account>"

### End of Configuration Lines ###

class eit-cacert {
	# Download the CA cert
	file { 'create_ca_folder':
        	path    => "/etc/openldap/cacerts",
        	ensure  => directory,
		require => Host['ad dns2'],
	}

	exec { 'retrieve_ca_cert_bundle':
        	command => "/usr/bin/wget -O /etc/openldap/cacerts/eit-root-ca.pem https://s3-ap-southeast-1.amazonaws.com/se-files/eit-root-ca.pem",
        	creates => "/etc/openldap/cacerts/eit-root-ca.pem",
		require => [File['create_ca_folder'], Package['install_wget']]
	}

}

class ssh-ad-wrapper {

# Download the SSH LDAP AD Wrapper
	exec { 'retrieve_ssh_ldap_ad_wrapper':
        	command => "/usr/bin/wget -O /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386 https://s3-ap-southeast-1.amazonaws.com/se-files/ssh-ldap-ad-wrapper-i386 && chmod +x /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386",
        	creates => "/usr/libexec/openssh/ssh-ldap-ad-wrapper-i386",
		require => Exec['retrieve_ca_cert_bundle'],
	}
}

class setup-nsswitch {
	# NSSwitch
	file_line { 'nspasswd':
        	line => 'passwd:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^passwd:',
        	replace => true,
		require => File_line['ssh_allowed_users'],
	}

	file_line { 'nsshadow':
        	line => 'shadow:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^shadow:',
        	replace => true,
		require => File_line['nspasswd']
	}	

	file_line { 'nsgroup':
        	line => 'group:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^group:',
        	replace => true,
		require => File_line['nsshadow']
	}

	file_line { 'nssudo':
        	line => 'sudoers:    ldap files',
        	path => "/etc/nsswitch.conf",
        	match => '^sudoers:',
        	replace => true,
		require => File_line['nsgroup'],
	}
}


class setup-pam {

	# It's Time for PAM
	file_line { 'pam_auth':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "auth        sufficient    pam_ldap.so use_first_pass",
        	after => '^auth\s*requisite\s*pam_succeed_if.so.*',
		require => File['/etc/sudo-ldap.conf'],
	}

	file_line { 'pam_account':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "account     [default=bad success=ok user_unknown=ignore] pam_ldap.so",
        	after => '^account\s*sufficient\s*pam_succeed_if.so.*',
		require => File_line['pam_auth'],
	}

	file_line { 'pam_password':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "password    sufficient    pam_ldap.so use_authtok",
        	after => '^password\s*sufficient\s*pam_unix.so.*',
		require => File_line['pam_account'],
	}

	file_line { 'pam_session':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "session     optional      pam_ldap.so",
        	after => '^session\s*required\s*pam_unix.so.*',
		require => File_line['pam_password'],
	}

	file_line { 'pam_session_mkdir':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "session     optional      pam_mkhomedir.so",
        	after => '^session\s*optional\s*pam_ldap.so.*',
		require => File_line['pam_session'],
	}

	file_line { 'pam_remove_localuser':
        	path => "/etc/pam.d/system-auth",
        	line => '# auth        [default=1 ignore=ignore success=ok] pam_localuser.so',
    		match => 'auth.*[default=1 ignore=ignore success=ok].*pam_localuser.so',
    		replace => true,
    		require => File['/etc/sudo-ldap.conf'],
  	}

	file { '/etc/pam.d/system-auth':
        	ensure => link,
        	target => "/etc/pam.d/password-auth-ac",
		require => File_line['pam_session_mkdir'],
	}
	
	# LDAP PAM Config
	file { '/etc/pam_ldap.conf':
        	ensure => link,
        	target => "/etc/ldap.conf",
		require => File['/etc/pam.d/system-auth'],
	}
}

class setup-ssh {
# Setup SSHd AuthorizedKeysCommand
	file_line { 'ssh_authorized_keys_command':
        	path => "/etc/ssh/sshd_config",
        	line => 'AuthorizedKeysCommand /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386',
		match => '^AuthorizedKeysCommand\s+.*',
		replace => true,
		require => Exec['retrieve_ssh_ldap_ad_wrapper'],
	}

	# AuthorizedKeysCommandUser is not supported prior to openSSH v6.2
	if ($::sshd_version >= 6.2) {
		file_line { 'ssh_authorized_keys_command_user':
			ensure => present,
			path => "/etc/ssh/sshd_config",
			line => 'AuthorizedKeysCommandUser root',
			match => '^AuthorizedKeysCommandUser',
			replace => true,
			require => File_line['ssh_authorized_keys_command'],
		}
	} else {
                file_line { 'ssh_authorized_keys_command_user':
                        ensure => present,
                        path => "/etc/ssh/sshd_config",
                        line => 'AuthorizedKeysCommandRunAs root',
                        match => '^AuthorizedKeysCommandRunAs',
			replace => true,
			require => File_line['ssh_authorized_keys_command'],
                }
	}
	
	file_line { 'ssh_allowed_users':
        	path => "/etc/ssh/sshd_config",
        	line => "AllowGroups $linux_breakglass_account $ad_ssh_allow_groups",
		match => '^AllowGroups',
		replace => true,
		require => File_line['ssh_authorized_keys_command_user'],
	}

}

class setup-main-config {

	# Main LDAP config

	$ldap_conf_template = "# Managed by Puppet, do not edit manually\n\nldap_version 3\nuri ldap://$ad_hostname_1:$ad_port_1\nuri ldap://$ad_hostname_2:$ad_port_2\nbase $ad_base_search\nbinddn $ad_binddn\nbindpw $ad_bindpw\ntimelimit 5\nbind_timelimit 10\nidle_timelimit 3600\npagesize 1000\nreferrals no\nscope sub\n\nssl start_tls\ntls_cacertfile /etc/openldap/cacerts/eit-root-ca.pem\ntls_reqcert demand\n\nfilter passwd (&(&(objectClass=person)(uidNumber=*)(gidNumber=*))(unixHomeDirectory=*))\nfilter shadow (&(&(objectClass=person)(uidNumber=*)(gidNumber=*))(unixHomeDirectory=*))\nfilter group  (&(objectClass=group)(gidNumber=*))\n\nmap    passwd   uid                     sAMAccountName\nmap    passwd   homeDirectory           unixHomeDirectory\nmap    passwd   gecos                   displayname\nmap    passwd   userPassword            \'\'\nmap    passwd   loginShell              loginShell\nmap    shadow   uid                     sAMAccountName\nmap    shadow   shadowLastChange        pwdLastSet\n"

	file { '/etc/ldap.conf':
        	ensure => file,
        	content => inline_template($ldap_conf_template),
        	mode => 600,
		require => File_line['nssudo'],
	}

	# Setup nslcd.conf
	file { '/etc/nslcd.conf':
        	ensure => link,
        	target => "/etc/ldap.conf",
		require => File['/etc/ldap.conf'],
	}

	# Setup sudo LDAP config
	$sudo_ldap_conf_template = "$ldap_conf_template\n\n# Sudo\nsudoers_base $ad_sudo_base_search"

	file { '/etc/sudo-ldap.conf':
        	ensure => file,
        	content => inline_template($sudo_ldap_conf_template),
        	mode => 600,
		require => File['/etc/nslcd.conf'],
	}

}

class setup-dns {
	# Add AD hostname in /etc/hosts
	host { 'ad dns1':
        	name    => $ad_hostname_1,
        	ip      => $ad_ip_1,
        	ensure  => present,
		require => [Package['install_openssh-ldap'], Package['install_nss-pam-ldapd']]
	}

        host { 'ad dns2':
                name    => $ad_hostname_2,
                ip      => $ad_ip_2,
                ensure  => present,
		require => Host['ad dns1'],
        }
}

class setup-services {

	# Manage the services
	service { 'sshd':
        	ensure => running,
        	name => "sshd",
        	enable => true,
        	subscribe => [File_line['ssh_authorized_keys_command'], File_line['ssh_allowed_users'], File_line['ssh_authorized_keys_command_user']],
	}

	service { 'nslcd':
        	ensure => running,
        	name => "nslcd",
        	enable => true,
        	subscribe => [File['/etc/ldap.conf'], Exec['retrieve_ca_cert_bundle']],
	}

	service { 'nscd':
        	ensure => running,
        	name => "nscd",
        	enable => true,
        	subscribe => [File['/etc/ldap.conf'], Exec['retrieve_ca_cert_bundle']],
	}
}

class install-packages {

	$required_packages = ['openssh-ldap', 'nss-pam-ldapd', 'sudo', 'wget']
	package { 'install_openssh-ldap':
		name => "openssh-ldap",
		ensure => present,
		require => Package['install_nss-pam-ldapd'],
	}

        package { 'install_nss-pam-ldapd':
                name => "nss-pam-ldapd",
                ensure => present,
		require => Package['install_sudo'],
        }	

        package { 'install_sudo':
                name => "sudo",
                ensure => present,
		require => Package['install_wget'],
        }

        package { 'install_wget':
                name => "wget",
                ensure => present,
        }
	
}

include install-packages
include setup-dns
include eit-cacert
include ssh-ad-wrapper
include setup-nsswitch
include setup-main-config
include setup-pam
include setup-ssh
include setup-services
