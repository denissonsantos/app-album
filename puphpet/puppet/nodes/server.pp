## Begin Server manifest

if $server_values == undef {
  $server_values = hiera('server', false)
} if $vm_values == undef {
  $vm_values = hiera($::vm_target_key, false)
}
# Ensure the time is accurate, reducing the possibilities of apt repositories
# failing for invalid certificates
class { 'ntp': }

include swap_file

include 'puphpet'
include 'puphpet::params'

Exec { path => [ '/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/' ] }
group { 'puppet':   ensure => present }
group { 'www-data': ensure => present }
group { 'www-user': ensure => present }

user { $::ssh_username:
  shell   => '/bin/bash',
  home    => "/home/${::ssh_username}",
  ensure  => present,
  groups  => ['www-data', 'www-user'],
  require => [Group['www-data'], Group['www-user']]
}

user { ['apache', 'nginx', 'httpd', 'www-data']:
  shell  => '/bin/bash',
  ensure => present,
  groups => 'www-data',
  require => Group['www-data']
}

file { "/home/${::ssh_username}":
  ensure => directory,
  owner  => $::ssh_username,
}

# copy dot files to ssh user's home directory
exec { 'dotfiles':
  cwd     => "/home/${::ssh_username}",
  command => "cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /home/${::ssh_username}/ \
              && chown -R ${::ssh_username} /home/${::ssh_username}/.[a-zA-Z0-9]* \
              && cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /root/",
  onlyif  => 'test -d /vagrant/puphpet/files/dot',
  returns => [0, 1],
  require => User[$::ssh_username]
}

case $::osfamily {
  # debian, ubuntu
  'debian': {
    class { 'apt': }

    Class['::apt::update'] -> Package <|
        title != 'python-software-properties'
    and title != 'software-properties-common'
    |>

    if ! defined(Package['augeas-tools']) {
      package { 'augeas-tools':
        ensure => present,
      }
    }
  }
  # redhat, centos
  'redhat': {
    class { 'yum': extrarepo => ['epel'] }

    class { 'yum::repo::rpmforge': }
    class { 'yum::repo::repoforgeextras': }

    Class['::yum'] -> Yum::Managed_yumrepo <| |> -> Package <| |>

    if ! defined(Package['git']) {
      package { 'git':
        ensure  => latest,
        require => Class['yum::repo::repoforgeextras']
      }
    }

    file_line { 'link ~/.bash_git':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => Exec['dotfiles'],
    }

    file_line { 'link ~/.bash_git for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => '/root/.bashrc',
      require => Exec['dotfiles'],
    }

    file_line { 'link ~/.bash_aliases':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => Exec['dotfiles'],
    }

    file_line { 'link ~/.bash_aliases for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => '/root/.bashrc',
      require => Exec['dotfiles'],
    }

    ensure_packages( ['augeas'] )
  }
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

case $::operatingsystem {
  'debian': {
    include apt::backports

    add_dotdeb { 'packages.dotdeb.org': release => $lsbdistcodename }

    $server_lsbdistcodename = downcase($lsbdistcodename)

    apt::force { 'git':
      release => "${server_lsbdistcodename}-backports",
      timeout => 60
    }
  }
  'ubuntu': {
    apt::key { '4F4EA0AAE5267A6C':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }
    apt::key { '4CBEDD5A':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }

    if $lsbdistcodename in ['lucid', 'precise'] {
      apt::ppa { 'ppa:pdoes/ppa': require => Apt::Key['4CBEDD5A'], options => '' }
    } else {
      apt::ppa { 'ppa:pdoes/ppa': require => Apt::Key['4CBEDD5A'] }
    }
  }
  'redhat', 'centos': {
    #
  }
}

if is_array($server_values['packages']) and count($server_values['packages']) > 0 {
  each( $server_values['packages'] ) |$package| {
    if ! defined(Package[$package]) {
      package { $package:
        ensure => present,
      }
    }
  }
}

define add_dotdeb ($release){
   apt::source { "${name}-repo.puphpet":
    location          => 'http://repo.puphpet.com/dotdeb/',
    release           => $release,
    repos             => 'all',
    required_packages => 'debian-keyring debian-archive-keyring',
    key               => '89DF5277',
    key_server        => 'keys.gnupg.net',
    include_src       => true
  }
}

# Begin open ports for iptables
if has_key($vm_values, 'vm')
  and has_key($vm_values['vm'], 'network')
  and has_key($vm_values['vm']['network'], 'forwarded_port')
{
  create_resources( iptables_port, $vm_values['vm']['network']['forwarded_port'] )
}

if has_key($vm_values, 'ssh') and has_key($vm_values['ssh'], 'port') {
  $vm_values_ssh_port = $vm_values['ssh']['port'] ? {
    ''      => 22,
    undef   => 22,
    0       => 22,
    default => $vm_values['ssh']['port']
  }

  if ! defined(Firewall["100 tcp/${vm_values_ssh_port}"]) {
    firewall { "100 tcp/${vm_values_ssh_port}":
      port   => $vm_values_ssh_port,
      proto  => tcp,
      action => 'accept',
      before => Class['my_fw::post']
    }
  }
}

define iptables_port (
  $host,
  $guest,
) {
  if ! defined(Firewall["100 tcp/${guest}"]) {
    firewall { "100 tcp/${guest}":
      port   => $guest,
      proto  => tcp,
      action => 'accept',
    }
  }
}

