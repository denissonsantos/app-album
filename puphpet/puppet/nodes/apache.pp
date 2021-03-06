## Begin Apache manifest

if $yaml_values == undef {
  $yaml_values = loadyaml('/vagrant/puphpet/config.yaml')
} if $apache_values == undef {
  $apache_values = $yaml_values['apache']
} if $php_values == undef {
  $php_values = hiera('php', false)
} if $hhvm_values == undef {
  $hhvm_values = hiera('hhvm', false)
}

if hash_key_equals($apache_values, 'install', 1) {
  include puphpet::params
  include apache::params

  $webroot_location      = $puphpet::params::apache_webroot_location
  $apache_provider_types = ['virtualbox', 'vmware_fusion', 'vmware_desktop', 'parallels']

  exec { "exec mkdir -p ${webroot_location}":
    command => "mkdir -p ${webroot_location}",
    creates => $webroot_location,
  }

  if (downcase($::provisioner_type) in $apache_provider_types) and ! defined(File[$webroot_location]) {
    file { $webroot_location:
      ensure  => directory,
      mode    => 0775,
      require => [
        Exec["exec mkdir -p ${webroot_location}"],
        Group['www-data']
      ]
    }
  } elsif ! (downcase($::provisioner_type) in $apache_provider_types) and ! defined(File[$webroot_location]) {
    file { $webroot_location:
      ensure  => directory,
      group   => 'www-data',
      mode    => 0775,
      require => [
        Exec["exec mkdir -p ${webroot_location}"],
        Group['www-data']
      ]
    }
  }

  if hash_key_equals($hhvm_values, 'install', 1) {
    $mpm_module           = 'worker'
    $disallowed_modules   = ['php']
    $apache_conf_template = 'puphpet/apache/hhvm-httpd.conf.erb'
    $apache_php_package   = 'hhvm'
  } elsif hash_key_equals($php_values, 'install', 1) {
    $mpm_module           = 'prefork'
    $disallowed_modules   = []
    $apache_conf_template = $apache::params::conf_template
    $apache_php_package   = 'php'
  } else {
    $mpm_module           = 'prefork'
    $disallowed_modules   = []
    $apache_conf_template = $apache::params::conf_template
    $apache_php_package   = ''
  }

  if $::operatingsystem == 'ubuntu'
    and hash_key_equals($php_values, 'install', 1)
    and hash_key_equals($php_values, 'version', 55)
  {
    $apache_version = '2.4'
  } else {
    $apache_version = $apache::version::default
  }

  $apache_settings = merge($apache_values['settings'], {
    'default_vhost'  => false,
    'mpm_module'     => $mpm_module,
    'conf_template'  => $apache_conf_template,
    'sendfile'       => $apache_values['settings']['sendfile'] ? { 1 => 'On', default => 'Off' },
    'apache_version' => $apache_version
  })

  create_resources('class', { 'apache' => $apache_settings })

  if hash_key_equals($apache_values, 'mod_pagespeed', 1) {
    class { 'puphpet::apache::modpagespeed': }
  }

  if hash_key_equals($apache_values, 'mod_spdy', 1) {
    class { 'puphpet::apache::modspdy':
      php_package => $apache_php_package
    }
  }

  if $apache_values['settings']['default_vhost'] == true {
    $apache_vhosts = merge($apache_values['vhosts'], {
      'default_vhost_80'  => {
        'servername'    => 'default',
        'docroot'       => '/var/www/default',
        'port'          => 80,
        'default_vhost' => true,
      },
      'default_vhost_443' => {
        'servername'    => 'default',
        'docroot'       => '/var/www/default',
        'port'          => 443,
        'default_vhost' => true,
        'ssl'           => 1,
      },
    })
  } else {
    $apache_vhosts = $apache_values['vhosts']
  }

  if count($apache_vhosts) > 0 {
    each( $apache_vhosts ) |$key, $vhost| {
      exec { "exec mkdir -p ${vhost['docroot']} @ key ${key}":
        command => "mkdir -p ${vhost['docroot']}",
        creates => $vhost['docroot'],
      }

      if (downcase($::provisioner_type) in $apache_provider_types)
        and ! defined(File[$vhost['docroot']])
      {
        file { $vhost['docroot']:
          ensure  => directory,
          mode    => 0765,
          require => Exec["exec mkdir -p ${vhost['docroot']} @ key ${key}"]
        }
      } elsif !(downcase($::provisioner_type) in $apache_provider_types)
        and ! defined(File[$vhost['docroot']])
      {
        file { $vhost['docroot']:
          ensure  => directory,
          group   => 'www-user',
          mode    => 0765,
          require => [
            Exec["exec mkdir -p ${vhost['docroot']} @ key ${key}"],
            Group['www-user']
          ]
        }
      }

      create_resources(apache::vhost, { "${key}" => merge($vhost, {
          'custom_fragment' => template('puphpet/apache/custom_fragment.erb'),
          'ssl'             => 'ssl' in $vhost and str2bool($vhost['ssl']) ? { true => true, default => false },
          'ssl_cert'        => hash_key_true($vhost, 'ssl_cert')      ? { true => $vhost['ssl_cert'],      default => undef },
          'ssl_key'         => hash_key_true($vhost, 'ssl_key')       ? { true => $vhost['ssl_key'],       default => undef },
          'ssl_chain'       => hash_key_true($vhost, 'ssl_chain')     ? { true => $vhost['ssl_chain'],     default => undef },
          'ssl_certs_dir'   => hash_key_true($vhost, 'ssl_certs_dir') ? { true => $vhost['ssl_certs_dir'], default => undef }
        })
      })

      if ! defined(Firewall["100 tcp/${vhost['port']}"]) {
        firewall { "100 tcp/${vhost['port']}":
          port   => $vhost['port'],
          proto  => tcp,
          action => 'accept',
        }
      }
    }
  }

  if ! defined(Firewall['100 tcp/443']) {
    firewall { '100 tcp/443':
      port   => 443,
      proto  => tcp,
      action => 'accept',
    }
  }

  if count($apache_values['modules']) > 0 {
    apache_mod { $apache_values['modules']: }
  }
}

define apache_mod {
  if ! defined(Class["apache::mod::${name}"]) and !($name in $disallowed_modules) {
    class { "apache::mod::${name}": }
  }
}

