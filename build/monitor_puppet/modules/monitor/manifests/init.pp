class logstash {
    service { 'monit':
        ensure => running,
        enable => true,
    }

    file { '/etc/monit.d/mysql':
        source => 'puppet:///modules/monitor/monit.d/mysql',
        notify => Service['monit'],
    }
}
