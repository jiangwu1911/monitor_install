class monitor {
    service { 'mysql':
        ensure => stopped,
	    enable => false,
    } 

    service { 'monit':
        ensure => running,
        enable => true,
    }

    file { '/etc/monit.d/mysql':
        source => 'puppet:///modules/monitor/monit.d/mysql',
        notify => Service['monit'],
    }

    file { '/etc/monitrc':
        source => 'puppet:///modules/monitor/monitrc',
        notify => Service['monit'],
    }
}
