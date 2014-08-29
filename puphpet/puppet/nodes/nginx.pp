## Begin Nginx manifest

if $nginx_values == undef {
   $nginx_values = hiera('nginx', false)
} if $php_values == undef {
   $php_values = hiera('php', false)
} if $hhvm_values == undef {
  $hhvm_values = hiera('hhvm', false)
}

if hash_key_equals($nginx_values, 'install', 1) {
  include nginx::params
  include puphpet::params

  Class['puphpet::ssl_cert'] -> Nginx::Resource::Vhost <| |>

  class { 'puphpet::ssl_cert': }

  if $lsbdistcodename == 'lucid' and hash_key_equals($php_values, 'version', '53') {
    apt::key { '67E15F46': key_server => 'hkp://keyserver.ubuntu.com:80' }
    apt::ppa { 'ppa:l-mierzwa/lucid-php5':
      options => '',
      require => Apt::Key['67E15F46']
    }
  }

  $webroot_location     = $puphpet::params::nginx_webroot_location
  $nginx_provider_types = ['virtualbox', 'vmware_fusion', 'vmware_desktop', 'parallels']

  exec { "exec mkdir -p ${webroot_location}":
    command => "mkdir -p ${webroot_location}",
    creates => $webroot_location,
  }

  if (downcase($::provisioner_type) in $nginx_provider_types) and ! defined(File[$webroot_location]) {
    file { $webroot_location:
      ensure  => directory,
      mode    => 0775,
      require => Exec["exec mkdir -p ${webroot_location}"],
    }
  } elsif ! (downcase($::provisioner_type) in $nginx_provider_types) and ! defined(File[$webroot_location]) {
    file { $webroot_location:
      ensure  => directory,
      mode    => 0775,
      group   => 'www-data',
      require => [
        Exec["exec mkdir -p ${webroot_location}"],
        Group['www-data']
      ]
    }
  }

  if $::osfamily == 'redhat' {
      file { '/usr/share/nginx':
        ensure  => directory,
        mode    => 0775,
        owner   => 'www-data',
        group   => 'www-data',
        require => Group['www-data'],
        before  => Package['nginx']
      }
  }

  if hash_key_equals($php_values, 'install', 1) {
    $php5_fpm_sock = '/var/run/php5-fpm.sock'

    $fastcgi_pass = $php_values['version'] ? {
      '53'    => '127.0.0.1:9000',
      undef   => null,
      default => "unix:${php5_fpm_sock}"
    }

    if $::osfamily == 'redhat' and $fastcgi_pass == "unix:${php5_fpm_sock}" {
      exec { "create ${php5_fpm_sock} file":
        command => "touch ${php5_fpm_sock}",
        onlyif  => ["test ! -f ${php5_fpm_sock}", "test ! -f ${php5_fpm_sock}="],
        require => Package['nginx'],
      }

      exec { "'listen = 127.0.0.1:9000' => 'listen = ${php5_fpm_sock}'":
        command => "perl -p -i -e 's#listen = 127.0.0.1:9000#listen = ${php5_fpm_sock}#gi' /etc/php-fpm.d/www.conf",
        unless  => "grep -c 'listen = 127.0.0.1:9000' '${php5_fpm_sock}'",
        notify  => [
          Class['nginx::service'],
          Service['php-fpm']
        ],
        require => Exec["create ${php5_fpm_sock} file"]
      }

      set_nginx_php5_fpm_sock_group_and_user { 'php_rhel':
        require => Exec["create ${php5_fpm_sock} file"],
      }
    } else {
      set_nginx_php5_fpm_sock_group_and_user { 'php':
        require   => Package['nginx'],
        subscribe => Service['php5-fpm'],
      }
    }
  } elsif hash_key_equals($hhvm_values, 'install', 1) {
    $fastcgi_pass = '127.0.0.1:9000'
  } else {
    $fastcgi_pass = null
  }

  class { 'nginx': }

  if hash_key_equals($nginx_values['settings'], 'default_vhost', 1) {
    $nginx_vhosts = merge($nginx_values['vhosts'], {
      'default' => {
        'server_name'    => '_',
        'server_aliases' => [],
        'www_root'       => '/var/www/html',
        'listen_port'    => 80,
        'index_files'    => ['index', 'index.html', 'index.htm', 'index.php'],
        'envvars'        => [],
        'ssl'            => '0',
        'ssl_cert'       => '',
        'ssl_key'        => '',
      },
    })

    if ! defined(File[$puphpet::params::nginx_default_conf_location]) {
      file { $puphpet::params::nginx_default_conf_location:
        ensure  => absent,
        require => Package['nginx'],
        notify  => Class['nginx::service'],
      }
    }
  } else {
    $nginx_vhosts = $nginx_values['vhosts']
  }

  if count($nginx_vhosts) > 0 {
    each( $nginx_vhosts ) |$key, $vhost| {
      exec { "exec mkdir -p ${vhost['www_root']} @ key ${key}":
        command => "mkdir -p ${vhost['www_root']}",
        creates => $vhost['www_root'],
      }

      if ! defined(File[$vhost['www_root']]) {
        file { $vhost['www_root']:
          ensure  => directory,
          require => Exec["exec mkdir -p ${vhost['www_root']} @ key ${key}"]
        }
      }

      if ! defined(Firewall["100 tcp/${vhost['listen_port']}"]) {
        firewall { "100 tcp/${vhost['listen_port']}":
          port   => $vhost['listen_port'],
          proto  => tcp,
          action => 'accept',
        }
      }
    }

    create_resources(nginx_vhost, $nginx_vhosts)
  }

  if ! defined(Firewall['100 tcp/443']) {
    firewall { '100 tcp/443':
      port   => 443,
      proto  => tcp,
      action => 'accept',
    }
  }
}

define nginx_vhost (
  $server_name,
  $server_aliases = [],
  $www_root,
  $listen_port,
  $index_files,
  $envvars = [],
  $ssl = false,
  $ssl_cert = $puphpet::params::ssl_cert_location,
  $ssl_key = $puphpet::params::ssl_key_location,
  $ssl_port = '443',
  $rewrite_to_https = false,
  $spdy = $nginx::params::nx_spdy,
){
  $merged_server_name = concat([$server_name], $server_aliases)

  if is_array($index_files) and count($index_files) > 0 {
    $try_files = $index_files[count($index_files) - 1]
  } else {
    $try_files = 'index.php'
  }

  if hash_key_equals($php_values, 'install', 1) {
    $fastcgi_param_parts = [
      'PATH_INFO $fastcgi_path_info',
      'PATH_TRANSLATED $document_root$fastcgi_path_info',
      'SCRIPT_FILENAME $document_root$fastcgi_script_name'
    ]
  } elsif hash_key_equals($hhvm_values, 'install', 1) {
    $fastcgi_param_parts = [
      'SCRIPT_FILENAME $document_root$fastcgi_script_name'
    ]
  } else {
    $fastcgi_param_parts = []
  }

  $ssl_set              = value_true($ssl)              ? { true => true,      default => false, }
  $ssl_cert_set         = value_true($ssl_cert)         ? { true => $ssl_cert, default => $puphpet::params::ssl_cert_location, }
  $ssl_key_set          = value_true($ssl_key)          ? { true => $ssl_key,  default => $puphpet::params::ssl_key_location, }
  $ssl_port_set         = value_true($ssl_port)         ? { true => $ssl_port, default => '443', }
  $rewrite_to_https_set = value_true($rewrite_to_https) ? { true => true,      default => false, }
  $spdy_set             = value_true($spdy)             ? { true => on,        default => off, }

  nginx::resource::vhost { $server_name:
    server_name      => $merged_server_name,
    www_root         => $www_root,
    listen_port      => $listen_port,
    index_files      => $index_files,
    try_files        => ['$uri', '$uri/', "/${try_files}?\$args"],
    ssl              => $ssl_set,
    ssl_cert         => $ssl_cert_set,
    ssl_key          => $ssl_key_set,
    ssl_port         => $ssl_port_set,
    rewrite_to_https => $rewrite_to_https_set,
    spdy             => $spdy_set,
    vhost_cfg_append => {
       sendfile => 'off'
    }
  }

  $fastcgi_param = concat($fastcgi_param_parts, $envvars)

  $fastcgi_pass_hash = fastcgi_pass ? {
    null    => {},
    ''      => {},
    default => {'fastcgi_pass' => $fastcgi_pass},
  }

  $location_cfg_append = merge({
    'fastcgi_split_path_info' => '^(.+\.php)(/.+)$',
    'fastcgi_param'           => $fastcgi_param,
    'fastcgi_index'           => 'index.php',
    'include'                 => 'fastcgi_params'
  }, $fastcgi_pass_hash)

  nginx::resource::location { "${server_name}-php":
    ensure              => present,
    vhost               => $server_name,
    location            => '~ \.php$',
    proxy               => undef,
    try_files           => ['$uri', '$uri/', "/${try_files}?\$args"],
    ssl                 => $ssl_set,
    www_root            => $www_root,
    location_cfg_append => $location_cfg_append,
    notify              => Class['nginx::service'],
  }
}

define set_nginx_php5_fpm_sock_group_and_user () {
  exec { 'set php5_fpm_sock group and user':
    command => "chmod 660 ${php5_fpm_sock} && \
                chown www-data ${php5_fpm_sock} && \
                chgrp www-data ${php5_fpm_sock} && \
                touch /.puphpet-stuff/php5_fpm_sock",
    creates => '/.puphpet-stuff/php5_fpm_sock',
  }
}

