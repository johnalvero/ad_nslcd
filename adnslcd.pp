# John Homer H Alvero
# 2 March 2018
# Voyager EIT SSH LDAP Integration
# 

$ad_ip=""
$ad_port="389"
$ad_hostname=""
$ad_binddn=""
$ad_bindpw=""
$ad_base_search="dc=launchpad,dc=corp,dc=voyagerinnovation,dc=com"
$ad_sudo_base_search="OU=SUDOers,OU=Security Groups,OU=Groups,$ad_base_search"
$ad_ssh_allow_groups="SE root"
$linux_breakglass_account="ec2-user"


### End of Configuration Lines ###

class eit-cacert {
	# Download the CA cert
	file { 'create_ca_folder':
        	path    => "/etc/openldap/cacerts",
        	ensure  => directory,
	}

	exec { 'retrieve_ca_cert_bundle':
        	command => "/usr/bin/wget -O /etc/openldap/cacerts/eit-root-ca.pem https://s3-ap-southeast-1.amazonaws.com/se-files/eit-root-ca.pem",
        	creates => "/etc/openldap/cacerts/eit-root-ca.pem",
		require => File['create_ca_folder'],
	}

}

class ssh-ad-wrapper {

# Download the SSH LDAP AD Wrapper
	exec { 'retrieve_ssh_ldap_ad_wrapper':
        	command => "/usr/bin/wget -O /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386 https://s3-ap-southeast-1.amazonaws.com/se-files/ssh-ldap-ad-wrapper-i386 && chmod +x /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386",
        	creates => "/usr/libexec/openssh/ssh-ldap-ad-wrapper-i386",
	}

	# Setup the SSH AD Public key wrapper config
	$ssh_ldap_ad_pubkey_template = "## Managed by Puppet, do not edit manually\n\nip $ad_ip\nport $ad_port\nhostname $ad_hostname\nbinddn $ad_binddn\nbindpw $ad_bindpw\nbase_search $ad_base_search\npubkey_property altSecurityIdentities\nserver_rootca /etc/openldap/cacerts/eit-root-ca.pem"

	file { '/etc/ssh-ldap-ad.conf':
        	ensure => file,
        	content => inline_template($ssh_ldap_ad_pubkey_template),
        	mode => 600,
        	require => Exec['retrieve_ssh_ldap_ad_wrapper'],
	}

}

class setup-nsswitch {
	# NSSwitch
	file_line { 'nspasswd':
        	line => 'passwd:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^passwd:',
        	replace => true,
	}

	file_line { 'nsshadow':
        	line => 'shadow:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^shadow:',
        	replace => true,
	}	

	file_line { 'nsgroup':
        	line => 'group:     files ldap',
        	path => "/etc/nsswitch.conf",
        	match => '^group:',
        	replace => true,
	}

	file_line { 'nssudo':
        	line => 'sudoers:    ldap files',
        	path => "/etc/nsswitch.conf",
        	match => '^sudo:',
        	replace => true,
	}
}


class setup-pam {

	# It's Time for PAM
	file_line { 'pam_auth':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "auth        sufficient    pam_ldap.so use_first_pass",
        	after => '^auth\s*requisite\s*pam_succeed_if.so.*',
	}

	file_line { 'pam_account':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "account     [default=bad success=ok user_unknown=ignore] pam_ldap.so",
        	after => '^account\s*sufficient\s*pam_succeed_if.so.*',
	}

	file_line { 'pam_password':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "password    sufficient    pam_ldap.so use_authtok",
        	after => '^password\s*sufficient\s*pam_unix.so.*',
	}

	file_line { 'pam_session':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "session     optional      pam_ldap.so",
        	after => '^session\s*required\s*pam_unix.so.*',
	}

	file_line { 'pam_session_mkdir':
        	path => "/etc/pam.d/password-auth-ac",
        	line => "session     optional      pam_mkhomedir.so",
        	after => '^session\s*optional\s*pam_ldap.so.*',
	}

	file { '/etc/pam.d/system-auth':
        	ensure => link,
        	target => "/etc/pam.d/password-auth-ac",
	}

	# LDAP PAM Config
	file { '/etc/pam_ldap.conf':
        	ensure => link,
        	target => "/etc/ldap.conf",
	}
}

class setup-ssh {
# Setup SSHd AuthorizedKeysCommand
	file_line { 'ssh_authorized_keys_command':
        	path => "/etc/ssh/sshd_config",
        	line => 'AuthorizedKeysCommand /usr/libexec/openssh/ssh-ldap-ad-wrapper-i386',
		match => '^AuthorizedKeysCommand',
		replace => true,
	}

	# AuthorizedKeysCommandUser is not supported prior to openSSH v6.2
        if ($::sshd_version >= 6.2) {
                file_line { 'ssh_authorized_keys_command_user':
                        ensure => present,
                        path => "/etc/ssh/sshd_config",
                        line => 'AuthorizedKeysCommandUser root',
                        match => '^AuthorizedKeysCommandUser',
                        replace => true,
                }
        } else {
                file_line { 'ssh_authorized_keys_command_user':
                        ensure => present,
                        path => "/etc/ssh/sshd_config",
                        line => 'AuthorizedKeysCommandRunAs root',
                        match => '^AuthorizedKeysCommandRunAs',
                        replace => true,
                }
        }
	
	file_line { 'ssh_allowed_users':
        	path => "/etc/ssh/sshd_config",
        	line => "AllowGroups $linux_breakglass_account $ad_ssh_allow_groups",
		match => '^AllowGroups',
		replace => true,
	}

}

class setup-main-config {

	# Main LDAP config

	$ldap_conf_template = "# Managed by Puppet, do not edit manually\n\nldap_version 3\nuri ldap://$ad_hostname:$ad_port\nbase $ad_base_search\nbinddn $ad_binddn\nbindpw $ad_bindpw\ntimelimit 5\nbind_timelimit 10\nidle_timelimit 3600\npagesize 1000\nreferrals no\nscope sub\n\nssl start_tls\ntls_cacertfile /etc/openldap/cacerts/eit-root-ca.pem\ntls_reqcert demand\n\nfilter passwd (&(&(objectClass=person)(uidNumber=*)(gidNumber=*))(unixHomeDirectory=*))\nfilter shadow (&(&(objectClass=person)(uidNumber=*)(gidNumber=*))(unixHomeDirectory=*))\nfilter group  (&(objectClass=group)(gidNumber=*))\n\nmap    passwd   uid                     sAMAccountName\nmap    passwd   homeDirectory           unixHomeDirectory\nmap    passwd   gecos                   displayname\nmap    passwd   userPassword            \'\'\nmap    passwd   loginShell              loginShell\nmap    shadow   uid                     sAMAccountName\nmap    shadow   shadowLastChange        pwdLastSet\n"

	file { '/etc/ldap.conf':
        	ensure => file,
        	content => inline_template($ldap_conf_template),
        	mode => 600,
	}

	# Setup nslcd.conf
	file { '/etc/nslcd.conf':
        	ensure => link,
        	target => "/etc/ldap.conf",
	}

	# Setup sudo LDAP config
	$sudo_ldap_conf_template = "$ldap_conf_template\n\n# Sudo\nsudoers_base $ad_sudo_base_search"

	file { '/etc/sudo-ldap.conf':
        	ensure => file,
        	content => inline_template($sudo_ldap_conf_template),
        	mode => 600,
	}

}

class setup-dns {
	# Add AD hostname in /etc/hosts
	host { 'ad dns':
        	name    => $ad_hostname,
        	ip      => $ad_ip,
        	ensure  => present,
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
	package { $required_packages: }

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
