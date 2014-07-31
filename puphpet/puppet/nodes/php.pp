## Begin PHP manifest

if $php_values == undef {
  $php_values = hiera('php', false)
} if $apache_values == undef {
  $apache_values = hiera('apache', false)
} if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
} if $mailcatcher_values == undef {
  $mailcatcher_values = hiera('mailcatcher', false)
}

if hash_key_equals($php_values, 'install', 1) {
  add_php_repos { 'add': }

  Class['Php'] -> Class['Php::Devel'] -> Php::Module <| |> -> Php::Pear::Module <| |> -> Php::Pecl::Module <| |>

  if $php_prefix == undef {
    $php_prefix = $::operatingsystem ? {
      /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => 'php5-',
      default                                 => 'php-',
    }
  }

  if $php_fpm_ini == undef {
    $php_fpm_ini = $::operatingsystem ? {
      /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => '/etc/php5/fpm/php.ini',
      default                                 => '/etc/php.ini',
    }
  }

  if hash_key_equals($apache_values, 'install', 1) {
    include apache::params

    if has_key($apache_values, 'mod_spdy') and $apache_values['mod_spdy'] == 1 {
      $php_webserver_service_ini = 'cgi'
    } else {
      $php_webserver_service_ini = 'httpd'
    }

    $php_webserver_service = 'httpd'
    $php_webserver_user    = $apache::params::user
    $php_webserver_restart = true

    class { 'php':
      service => $php_webserver_service
    }
  } elsif hash_key_equals($nginx_values, 'install', 1) {
    include nginx::params

    $php_webserver_service     = "${php_prefix}fpm"
    $php_webserver_service_ini = $php_webserver_service
    $php_webserver_user        = $nginx::params::nx_daemon_user
    $php_webserver_restart     = true

    class { 'php':
      package             => $php_webserver_service,
      service             => $php_webserver_service,
      service_autorestart => false,
      config_file         => $php_fpm_ini,
    }

    service { $php_webserver_service:
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      require    => Package[$php_webserver_service]
    }
  } else {
    $php_webserver_service     = undef
    $php_webserver_service_ini = undef
    $php_webserver_restart     = false

    class { 'php':
      package             => "${php_prefix}cli",
      service             => $php_webserver_service,
      service_autorestart => false,
    }
  }

  class { 'php::devel': }

  if count($php_values['modules']['php']) > 0 {
    php_mod { $php_values['modules']['php']:; }
  }
  if count($php_values['modules']['pear']) > 0 {
    php_pear_mod { $php_values['modules']['pear']:; }
  }
  if count($php_values['modules']['pecl']) > 0 {
    php_pecl_mod { $php_values['modules']['pecl']:; }
  }
  if count($php_values['ini']) > 0 {
    each( $php_values['ini'] ) |$key, $value| {
      if is_array($value) {
        each( $php_values['ini'][$key] ) |$innerkey, $innervalue| {
          puphpet::php::ini { "${key}_${innerkey}":
            entry       => "CUSTOM_${innerkey}/${key}",
            value       => $innervalue,
            php_version => $php_values['version'],
            webserver   => $php_webserver_service_ini
          }
        }
      } else {
        puphpet::php::ini { $key:
          entry       => "CUSTOM/${key}",
          value       => $value,
          php_version => $php_values['version'],
          webserver   => $php_webserver_service_ini
        }
      }
    }

    if $php_values['ini']['session.save_path'] != undef {
      $php_sess_save_path = $php_values['ini']['session.save_path']

      exec {"mkdir -p ${php_sess_save_path}":
        onlyif => "test ! -d ${php_sess_save_path}",
        before => Class['php']
      }
      exec {"chmod 775 ${php_sess_save_path} && chown www-data ${php_sess_save_path} && chgrp www-data ${php_sess_save_path}":
        require => Class['php']
      }
    }
  }

  puphpet::php::ini { $key:
    entry       => 'CUSTOM/date.timezone',
    value       => $php_values['timezone'],
    php_version => $php_values['version'],
    webserver   => $php_webserver_service_ini
  }

  if hash_key_equals($php_values, 'composer', 1) {
    $php_composer_home = $php_values['composer_home'] ? {
      false   => false,
      undef   => false,
      ''      => false,
      default => $php_values['composer_home'],
    }

    if $php_composer_home {
      file { $php_composer_home:
        ensure  => directory,
        owner   => 'www-data',
        group   => 'www-data',
        mode    => 0775,
        require => [Group['www-data'], Group['www-user']]
      }

      file_line { "COMPOSER_HOME=${php_composer_home}":
        path => '/etc/environment',
        line => "COMPOSER_HOME=${php_composer_home}",
      }
    }

    class { 'composer':
      target_dir      => '/usr/local/bin',
      composer_file   => 'composer',
      download_method => 'curl',
      logoutput       => false,
      tmp_path        => '/tmp',
      php_package     => "${php::params::module_prefix}cli",
      curl_package    => 'curl',
      suhosin_enabled => false,
    }
  }

  # Usually this would go within the library that needs in (Mailcatcher)
  # but the values required are sufficiently complex that it's easier to
  # add here
  if hash_key_equals($mailcatcher_values, 'install', 1)
    and ! defined(Puphpet::Php::Ini['sendmail_path'])
  {
    puphpet::php::ini { 'sendmail_path':
      entry       => 'CUSTOM/sendmail_path',
      value       => "${mailcatcher_values['settings']['mailcatcher_path']}/catchmail -f",
      php_version => $php_values['version'],
      webserver   => $php_webserver_service_ini
    }
  }
}

define php_mod {
  if ! defined(Puphpet::Php::Module[$name]) {
    puphpet::php::module { $name:
      service_autorestart => $php_webserver_restart,
    }
  }
}
define php_pear_mod {
  if ! defined(Puphpet::Php::Pear[$name]) {
    puphpet::php::pear { $name:
      service_autorestart => $php_webserver_restart,
    }
  }
}
define php_pecl_mod {
  if ! defined(Puphpet::Php::Extra_repos[$name]) {
    puphpet::php::extra_repos { $name:
      before => Puphpet::Php::Pecl[$name],
    }
  }

  if ! defined(Puphpet::Php::Pecl[$name]) {
    puphpet::php::pecl { $name:
      service_autorestart => $php_webserver_restart,
    }
  }
}

define add_php_repos {
  case $::operatingsystem {
    'debian': {
      # Debian Squeeze 6.0 can do PHP 5.3 (default) and 5.4
      if $::lsbdistcodename == 'squeeze' and $php_values['version'] == '54' {
        add_dotdeb { 'packages.dotdeb.org-php54': release => 'squeeze-php54' }
      }
      # Debian Wheezy 7.0 can do PHP 5.4 (default) and 5.5
      elsif $lsbdistcodename == 'wheezy' and $php_values['version'] == '55' {
        add_dotdeb { 'packages.dotdeb.org-php55': release => 'wheezy-php55' }
      }
    }
    'ubuntu': {
      # Ubuntu Lucid 10.04, Precise 12.04, Quantal 12.10 and Raring 13.04 can do PHP 5.3 (default <= 12.10) and 5.4 (default <= 13.04)
      if $lsbdistcodename in ['lucid', 'precise', 'quantal', 'raring', 'trusty'] and $php_values['version'] == '54' {
        if $lsbdistcodename == 'lucid' {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'], options => '' }
        } else {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'] }
        }
      }
      # Ubuntu 12.04/10, 13.04/10, 14.04 can do PHP 5.5
      elsif $lsbdistcodename in ['precise', 'quantal', 'raring', 'saucy', 'trusty'] and $php_values['version'] == '55' {
        apt::ppa { 'ppa:ondrej/php5': require => Apt::Key['4F4EA0AAE5267A6C'] }
      }
      elsif $lsbdistcodename in ['lucid'] and $php_values['version'] == '55' {
        err('You have chosen to install PHP 5.5 on Ubuntu 10.04 Lucid. This will probably not work!')
      }
      # Ubuntu 14.04 can do PHP 5.6
      elsif $lsbdistcodename == 'trusty' and $php_values['version'] == '56' {
        apt::ppa { 'ppa:ondrej/php5-5.6': require => Apt::Key['4F4EA0AAE5267A6C'] }
      }
    }
    'redhat', 'centos': {
      if $php_values['version'] == '54' {
        class { 'yum::repo::remi': }
      }
      # remi_php55 requires the remi repo as well
      elsif $php_values['version'] == '55' {
        class { 'yum::repo::remi': }
        class { 'yum::repo::remi_php55': }
      }
      # remi_php56 requires the remi repo as well
      elsif $php_values['version'] == '56' {
        class { 'yum::repo::remi': }
        yum::managed_yumrepo { 'remi-php56':
          descr          => 'Les RPM de remi pour Enterpise Linux $releasever - $basearch - PHP 5.6',
          mirrorlist     => 'http://rpms.famillecollet.com/enterprise/$releasever/php56/mirror',
          enabled        => 1,
          gpgcheck       => 1,
          gpgkey         => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-remi',
          gpgkey_source  => 'puppet:///modules/yum/rpm-gpg/RPM-GPG-KEY-remi',
          priority       => 1,
        }
      }
    }
  }
}

